import SwiftUI
import WebKit
import Combine
import Security
import UniformTypeIdentifiers

struct Bookmark: Identifiable, Codable {
    var id = UUID()
    let title: String
    let url: String
    var spaceID: String? = "personal"
}

final class BrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let webView: WKWebView
    let isPrivate: Bool
    let spaceID: String
    var onVisit: ((String, URL) -> Void)?
    var onPopup: ((URL) -> Void)?
    @Published var title = "New tab"
    @Published var url: URL?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var progress = 0.0
    @Published var isLoading = false
    // Each tab remembers its own immersive chrome state.
    @Published private(set) var hidesChrome = false
    private var previousScrollY: CGFloat = 0
    private var scrollTravel: CGFloat = 0
    private var scrollDirection: CGFloat = 0
    @Published var message: String?
    @Published private(set) var recoveryNotice: String?
    private var observations: [NSKeyValueObservation] = []
    private var recoveryPolicy = WebContentRecoveryPolicy()
    private var pendingRecovery: DispatchWorkItem?
    private var recoveryGeneration = UUID()
    private var currentNavigation: WKNavigation?
    private var recoveringNavigation = false
    private var isSelected = false
    private var isClosed = false

    init(isPrivate: Bool = false, space: BrowserSpace = BrowserSpace.defaults[0], privateStore: WKWebsiteDataStore? = nil) {
        self.isPrivate = isPrivate
        self.spaceID = space.id
        let configuration = WKWebViewConfiguration()
        // Personal keeps the original store, preserving sign-ins from version 0.7.
        configuration.websiteDataStore = isPrivate ? (privateStore ?? .nonPersistent()) : (space.id == "personal" ? .default() : WKWebsiteDataStore(forIdentifier: space.dataID))
        configuration.allowsInlineMediaPlayback = true
        // Cloudflare and other challenge widgets need ordinary page JavaScript.
        // Do not alter the user agent or suppress the page's cookies.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(Color.nivqoBackground)
        observations = [
            webView.observe(\.title, options: [.new]) { [weak self] web, _ in self?.title = web.title ?? "New tab" },
            webView.observe(\.url, options: [.new]) { [weak self] web, _ in
                // Process eviction can transiently clear WebKit's URL. Preserve
                // the requested page so it stays retryable instead of becoming home.
                // Explicit about:blank is still kept and never auto-reloaded.
                if let url = web.url { self?.url = url }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] web, _ in self?.canGoBack = web.canGoBack },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] web, _ in self?.canGoForward = web.canGoForward },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] web, _ in self?.progress = web.estimatedProgress },
            webView.observe(\.isLoading, options: [.new]) { [weak self] web, _ in self?.isLoading = web.isLoading },
            // Observe rather than replace WKWebView's own scroll-view delegate.
            webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
                self?.updateChromeForScroll(scroll)
            }
        ]
    }
    func setChromeHidden(_ hidden: Bool) {
        guard hidesChrome != hidden else { return }
        hidesChrome = hidden
        scrollTravel = 0
    }
    private func updateChromeForScroll(_ scroll: UIScrollView) {
        let y = max(0, scroll.contentOffset.y)
        let delta = y - previousScrollY
        previousScrollY = y
        // Ignore layout shifts, programmatic scrolling and short websites.
        guard scroll.isDragging || scroll.isDecelerating else { scrollTravel = 0; return }
        guard scroll.contentSize.height > scroll.bounds.height + 80 else {
            setChromeHidden(false); return
        }
        if y < 12 { setChromeHidden(false); return }
        guard abs(delta) < 100 && abs(delta) > 0.5 else { scrollTravel = 0; return }
        let direction: CGFloat = delta > 0 ? 1 : -1
        if direction != scrollDirection { scrollTravel = 0; scrollDirection = direction }
        scrollTravel += abs(delta)
        if direction > 0 && y > 90 && scrollTravel > 34 {
            setChromeHidden(true)
        } else if direction < 0 && scrollTravel > 26 {
            setChromeHidden(false)
        }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        currentNavigation = navigation
        setChromeHidden(false)
        previousScrollY = 0
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !isClosed, isCurrent(navigation) else { return }
        recoveryPolicy.navigationFinished()
        recoveringNavigation = false
        recoveryNotice = nil
        if !isPrivate, let url = webView.url, safeWebURL(url.absoluteString) != nil { onVisit?(webView.title ?? url.host ?? "Page", url) }
    }
    func load(_ url: URL) {
        guard !isClosed else { return }
        guard let safeURL = safeWebURL(url.absoluteString) else { message = "Only http and https pages can be opened."; return }
        prepareUserNavigation()
        self.url = safeURL
        setChromeHidden(false)
        currentNavigation = webView.load(URLRequest(url: safeURL))
    }
    /// Also used for the regular Reload action, so only user intent renews the budget.
    func retryPage() {
        guard !isClosed, let page = recoverableURL else { return }
        prepareUserNavigation()
        setChromeHidden(false)
        currentNavigation = webView.reload() ?? webView.load(URLRequest(url: page))
    }
    func goBack() {
        guard !isClosed, webView.canGoBack else { return }
        prepareUserNavigation()
        currentNavigation = webView.goBack()
    }
    func goForward() {
        guard !isClosed, webView.canGoForward else { return }
        prepareUserNavigation()
        currentNavigation = webView.goForward()
    }
    func dismissRecoveryNotice() { recoveryNotice = nil }
    func stopLoading() {
        cancelRecovery()
        recoveringNavigation = false
        webView.stopLoading()
    }
    func setSelected(_ selected: Bool) {
        isSelected = selected
        if !selected && pendingRecovery != nil {
            cancelRecovery()
            showRecoveryNotice()
        }
    }
    func close() {
        isClosed = true
        isSelected = false
        cancelRecovery()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        onVisit = nil
        onPopup = nil
    }
    private var recoverableURL: URL? {
        // An explicit about:blank must not fall back to a previous page URL.
        guard let candidate = webView.url ?? url else { return nil }
        return safeWebURL(candidate.absoluteString)
    }
    private func prepareUserNavigation() {
        cancelRecovery()
        recoveryPolicy.userInitiatedNavigation()
        recoveringNavigation = false
        recoveryNotice = nil
        message = nil
    }
    private func cancelRecovery() {
        recoveryGeneration = UUID()
        pendingRecovery?.cancel()
        pendingRecovery = nil
        recoveryPolicy.cancelScheduledReload()
    }
    private func isCurrent(_ navigation: WKNavigation?) -> Bool {
        guard let navigation = navigation, let current = currentNavigation else { return true }
        return navigation === current
    }
    private func showRecoveryNotice() {
        let text = "This page was interrupted. Tap Reload to try again."
        if recoveryNotice != text { recoveryNotice = text }
        setChromeHidden(false)
    }
    func search(_ input: String) {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if let direct = safeWebURL(value) { load(direct); return }
        if !value.contains(" "), !value.contains(":"), value.contains("."), let direct = safeWebURL("https://" + value) {
            load(direct); return
        }
        var components = URLComponents(string: "https://duckduckgo.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: value)]
        if let url = components.url { load(url) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        // Embedded verification challenges legitimately use non-network subframes.
        // Permit those inside WebKit; never navigate the main browser to them.
        let localSubframe = navigationAction.targetFrame?.isMainFrame == false &&
            ["about", "blob", "data"].contains(scheme)
        if safeWebURL(url.absoluteString) != nil || url.absoluteString == "about:blank" || localSubframe {
            // Policy callbacks cannot reliably establish user intent: even form
            // resubmission can be part of our automatic reload. Only explicit app
            // navigation/retry controls replenish the recovery budget.
            decisionHandler(.allow)
        } else {
            if navigationAction.targetFrame?.isMainFrame != false { message = "This link uses a scheme that NIVQO does not open." }
            decisionHandler(.cancel)
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { handle(error, navigation: navigation) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { handle(error, navigation: navigation) }
    private func handle(_ error: Error, navigation: WKNavigation?) {
        guard !isClosed, isCurrent(navigation) else { return }
        let failure = error as NSError
        if failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled { return }
        if failure.domain == WKError.errorDomain && failure.code == WKError.Code.webContentProcessTerminated.rawValue {
            recoverContentProcess()
        } else if recoveringNavigation {
            recoveryPolicy.automaticReloadFailed()
            recoveringNavigation = false
            showRecoveryNotice()
        } else {
            message = error.localizedDescription
        }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { recoverContentProcess() }
    private func recoverContentProcess() {
        let page = recoverableURL
        switch recoveryPolicy.processTerminated(url: page, isSelected: isSelected,
                                                isForeground: UIApplication.shared.applicationState == .active,
                                                isClosed: isClosed) {
        case .ignore:
            return
        case .showRetry:
            recoveringNavigation = false
            showRecoveryNotice()
        case .reload:
            // Coalesce the failure and termination delegates before touching WebKit.
            // No modal alert is produced by either callback, including on home tabs.
            let generation = recoveryGeneration
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, self.recoveryGeneration == generation else { return }
                self.pendingRecovery = nil
                guard !self.isClosed, self.isSelected,
                      UIApplication.shared.applicationState == .active,
                      let page = page, self.recoverableURL == page else {
                    self.recoveryPolicy.cancelScheduledReload()
                    if !self.isClosed && self.recoverableURL != nil { self.showRecoveryNotice() }
                    return
                }
                guard self.recoveryPolicy.beginAutomaticReload() else { return }
                self.recoveringNavigation = true
                self.currentNavigation = self.webView.reload() ?? self.webView.load(URLRequest(url: page))
                if self.currentNavigation == nil {
                    self.recoveryPolicy.automaticReloadFailed()
                    self.recoveringNavigation = false
                    self.showRecoveryNotice()
                }
            }
            pendingRecovery = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url, safeWebURL(url.absoluteString) != nil { onPopup?(url) }
        return nil
    }
}

final class BrowserModel: ObservableObject {
    @Published var tabs: [BrowserTab]
    @Published var selectedID: UUID { didSet { synchronizeSelection() } }
    @Published var bookmarks: [Bookmark]
    @Published var spaces: [BrowserSpace]
    @Published var activeSpaceID: String
    @Published var history: [HistoryItem]
    @Published private(set) var searchHistory: [SearchHistoryItem]
    @Published var accounts: [SavedAccount] = []
    @Published var notice: String?
    @Published var saveHistory = UserDefaults.standard.object(forKey: "nivqo.saveHistory") as? Bool ?? true { didSet { UserDefaults.standard.set(saveHistory, forKey: "nivqo.saveHistory") } }
    @Published var searchEngine = UserDefaults.standard.string(forKey: "nivqo.searchEngine") ?? "DuckDuckGo" { didSet { UserDefaults.standard.set(searchEngine, forKey: "nivqo.searchEngine") } }
    private var privateStores: [String: WKWebsiteDataStore] = [:]
    private struct RestoredTab: Codable { var url: String; var spaceID: String }
    private var tabObservers: [UUID: AnyCancellable] = [:]
    private func observe(_ tab: BrowserTab) { tabObservers[tab.id] = tab.objectWillChange.sink { [weak self] in self?.objectWillChange.send() } }
    private func synchronizeSelection() {
        for tab in tabs { tab.setSelected(tab.id == selectedID) }
    }
    init() {
        spaces = Self.read("nivqo.spaces") ?? BrowserSpace.defaults
        // Existing installations receive Gaming without overwriting their Spaces.
        if !spaces.contains(where: { $0.id == "gaming" }) {
            spaces.append(BrowserSpace(id: "gaming", name: "Gaming", hex: "ff5da8",
                                       dataID: UUID(uuidString: "9F483849-40D2-4548-B115-911B50F00A04")!))
            if let data = try? JSONEncoder().encode(spaces) {
                UserDefaults.standard.set(data, forKey: "nivqo.spaces")
            }
        }
        activeSpaceID = "personal"
        history = Self.read("nivqo.history") ?? []
        searchHistory = Self.read("nivqo.searchHistory.v1") ?? []
        let first = BrowserTab()
        tabs = [first]; selectedID = first.id
        bookmarks = (UserDefaults.standard.data(forKey: "nivqo.bookmarks").flatMap { try? JSONDecoder().decode([Bookmark].self, from: $0) } ?? []).filter { safeWebURL($0.url) != nil }
        observe(first)
        wire(first)
        first.setSelected(true)
        do { accounts = try PasswordVault.read().map(\.account) } catch { notice = error.localizedDescription }
        let restored: [RestoredTab] = Self.read("nivqo.tabs") ?? []
        if !restored.isEmpty {
            first.close()
            tabs = []; tabObservers.removeAll()
            for item in restored.prefix(30) {
                guard spaces.contains(where: { $0.id == item.spaceID }), let url = safeWebURL(item.url) else { continue }
                activeSpaceID = item.spaceID; newTab(url: url)
            }
            if tabs.isEmpty { activeSpaceID = "personal"; newTab() }
            else { select(tabs[0]) }
        }
    }
    var activeSpace: BrowserSpace { spaces.first(where: { $0.id == activeSpaceID }) ?? spaces[0] }
    var visibleTabs: [BrowserTab] { tabs.filter { $0.spaceID == activeSpaceID } }
    var visibleBookmarks: [Bookmark] { bookmarks.filter { ($0.spaceID ?? "personal") == activeSpaceID } }
    var visibleHistory: [HistoryItem] { history.filter { $0.spaceID == activeSpaceID } }
    var visibleSearchHistory: [SearchHistoryItem] { searchHistory.filter { $0.spaceID == activeSpaceID } }
    func recentSearches(matching input: String, in tab: BrowserTab) -> [SearchHistoryItem] {
        guard saveHistory, !tab.isPrivate else { return [] }
        return SearchHistory.matching(input, spaceID: tab.spaceID, in: searchHistory)
    }
    func clearSearchHistory() {
        searchHistory.removeAll { $0.spaceID == activeSpaceID }
        persist(searchHistory, "nivqo.searchHistory.v1")
    }
    func removeSearch(_ id: UUID) {
        searchHistory.removeAll { $0.id == id && $0.spaceID == activeSpaceID }
        persist(searchHistory, "nivqo.searchHistory.v1")
    }
    var visibleAccounts: [SavedAccount] { accounts.filter { $0.spaceID == activeSpaceID } }
    private static func read<T: Decodable>(_ key: String) -> T? { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) } }
    private func persist<T: Encodable>(_ value: T, _ key: String) { if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) } }
    private func wire(_ tab: BrowserTab) {
        tab.onVisit = { [weak self, weak tab] title, url in
            guard let self = self, let tab = tab, self.saveHistory, !tab.isPrivate else { return }
            self.history.removeAll { $0.spaceID == tab.spaceID && $0.url == url.absoluteString }
            self.history.insert(HistoryItem(title: title, url: url.absoluteString, spaceID: tab.spaceID), at: 0)
            self.history = Array(self.history.prefix(1000)); self.persist(self.history, "nivqo.history")
        }
        tab.onPopup = { [weak self, weak tab] url in
            guard let self = self, let tab = tab else { return }
            self.switchSpace(tab.spaceID); self.newTab(privateMode: tab.isPrivate, url: url)
        }
    }
    func switchSpace(_ id: String) {
        guard spaces.contains(where: { $0.id == id }) else { return }
        activeSpaceID = id
        if let tab = tabs.first(where: { $0.spaceID == id }) { selectedID = tab.id } else { newTab() }
    }
    func select(_ tab: BrowserTab) { activeSpaceID = tab.spaceID; selectedID = tab.id }
    func addSpace(_ name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 32, spaces.count < 12 else { notice = "Enter a name up to 32 characters. You can have 12 Spaces."; return }
        let space = BrowserSpace(id: UUID().uuidString, name: value, hex: ["27c9ff","8a83ff","61d7ac","ffa36d"][spaces.count % 4], dataID: UUID())
        spaces.append(space); persist(spaces, "nivqo.spaces"); switchSpace(space.id)
    }
    func search(_ input: String) {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if safeWebURL(value) != nil || (!value.contains(" ") && !value.contains(":") && value.contains(".")) { selected.search(value); return }
        // Only actual search phrases are saved: never direct URL navigations,
        // automatic redirects, or searches made in a private tab.
        if saveHistory && !selected.isPrivate {
            searchHistory = SearchHistory.recording(value, spaceID: selected.spaceID, in: searchHistory)
            persist(searchHistory, "nivqo.searchHistory.v1")
        }
        var components = URLComponents(string: searchEngine == "Google" ? "https://www.google.com/search" : searchEngine == "Brave" ? "https://search.brave.com/search" : "https://duckduckgo.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: value)]
        if let url = components.url { selected.load(url) }
    }
    var selected: BrowserTab { tabs.first(where: { $0.id == selectedID }) ?? tabs[0] }
    func newTab(privateMode: Bool = false, url: URL? = nil) {
        if privateMode && privateStores[activeSpaceID] == nil { privateStores[activeSpaceID] = .nonPersistent() }
        let tab = BrowserTab(isPrivate: privateMode, space: activeSpace, privateStore: privateStores[activeSpaceID])
        tabs.append(tab); observe(tab); wire(tab); selectedID = tab.id
        if let url = url { tab.load(url) }
    }
    func close(_ id: UUID) {
        tabs.first(where: { $0.id == id })?.close()
        tabs.removeAll { $0.id == id }; tabObservers.removeValue(forKey: id)
        for id in Array(privateStores.keys) where !tabs.contains(where: { $0.isPrivate && $0.spaceID == id }) { privateStores.removeValue(forKey: id) }
        if visibleTabs.isEmpty { newTab() }
        if !visibleTabs.contains(where: { $0.id == selectedID }) { selectedID = visibleTabs[0].id }
    }
    func bookmarkCurrent() {
        guard !selected.isPrivate, let url = selected.url, safeWebURL(url.absoluteString) != nil,
              !visibleBookmarks.contains(where: { $0.url == url.absoluteString }) else { return }
        bookmarks.append(Bookmark(title: selected.title, url: url.absoluteString, spaceID: activeSpaceID)); saveBookmarks()
    }
    func removeBookmarks(at offsets: IndexSet) { let ids = offsets.map { visibleBookmarks[$0].id }; bookmarks.removeAll { ids.contains($0.id) }; saveBookmarks() }
    private func saveBookmarks() { if let data = try? JSONEncoder().encode(bookmarks) { UserDefaults.standard.set(data, forKey: "nivqo.bookmarks") } }
    func clearWebsiteData() {
        for tab in tabs { tab.close() }
        for space in spaces {
            let store = space.id == "personal" ? WKWebsiteDataStore.default() : WKWebsiteDataStore(forIdentifier: space.dataID)
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
        }
        privateStores.removeAll(); tabObservers.removeAll(); tabs = []; newTab()
    }
    func clearHistory() {
        history.removeAll { $0.spaceID == activeSpaceID }
        searchHistory.removeAll { $0.spaceID == activeSpaceID }
        persist(history, "nivqo.history")
        persist(searchHistory, "nivqo.searchHistory.v1")
    }
    func saveSession() {
        persist(tabs.filter { !$0.isPrivate }.compactMap { tab in tab.url.map { RestoredTab(url: $0.absoluteString, spaceID: tab.spaceID) } }, "nivqo.tabs")
    }
    func commitImport(_ preview: BrowserImport) throws -> Int {
        guard Date().timeIntervalSince(preview.created) < 300, spaces.contains(where: { $0.id == preview.spaceID }) else { throw ImportParser.ParseError.invalid("This preview expired. Choose the file again.") }
        var count = 0
        if preview.passwords {
            var entries = try PasswordVault.read()
            for row in preview.rows {
                if entries.contains(where: { $0.account.spaceID == preview.spaceID && $0.account.url == row.url && $0.account.username == row.username }) { continue }
                guard entries.count < 5000 else { break }
                entries.append(PasswordVault.Entry(account: SavedAccount(title: row.title, url: row.url, username: row.username, spaceID: preview.spaceID), password: row.password)); count += 1
            }
            try PasswordVault.write(entries); accounts = entries.map(\.account)
        } else {
            for row in preview.rows {
                if bookmarks.contains(where: { ($0.spaceID ?? "personal") == preview.spaceID && $0.url == row.url }) { continue }
                guard bookmarks.count < 1000 else { break }
                bookmarks.append(Bookmark(title: row.title, url: row.url, spaceID: preview.spaceID)); count += 1
            }
            saveBookmarks()
        }
        return count
    }
    func copyAccount(_ id: UUID, password: Bool) throws {
        guard let entry = try PasswordVault.read().first(where: { $0.account.id == id && $0.account.spaceID == activeSpaceID }) else { return }
        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: password ? entry.password : entry.account.username]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(30)])
        notice = "Copied for 30 seconds. Paste it into the website’s sign-in form."
    }
    func deleteAccount(_ id: UUID) throws {
        let entries = try PasswordVault.read().filter { !($0.account.id == id && $0.account.spaceID == activeSpaceID) }
        try PasswordVault.write(entries); accounts = entries.map(\.account)
    }
}

enum PasswordVault {
    struct Entry: Codable { var account: SavedAccount; var password: String }
    static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.nivqo.iphone.accounts.v1", kSecAttrAccount as String: "vault"] }
    static func read() throws -> [Entry] {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = item as? Data else { throw failure(status) }
        return try JSONDecoder().decode([Entry].self, from: data)
    }
    static func write(_ entries: [Entry]) throws {
        let data = try JSONEncoder().encode(entries)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure(status) }
    }
    private static func failure(_ status: OSStatus) -> Error { ImportParser.ParseError.invalid("Keychain could not be accessed (\(status)). Unlock your iPhone and retry.") }
}
