import SwiftUI
import WebKit

struct BrowserView: View {
    @ObservedObject var browser: BrowserModel
    @ObservedObject var flow: FlowClient
    @State private var showingFlow = false
    @State private var showingTabs = false
    @State private var showingBookmarks = false
    @State private var clearConfirmation = false
    @State private var panel: String?
    private var accent: Color { Color(spaceHex: browser.activeSpace.hex) }

    var body: some View {
        BrowserPage(tab: browser.selected, browser: browser,
                    openFlow: { showingFlow = true }, openPanel: { panel = $0 },
                    openTabs: { showingTabs = true }, openBookmarks: { showingBookmarks = true },
                    clearData: { clearConfirmation = true })
        .id(browser.selectedID)
        .background(Color.nivqoBackground)
        .overlay(alignment: .top) { spaceAccent }
        .overlay(alignment: .bottom) { spaceAccent }
        .tint(accent)
        .sheet(isPresented: Binding(get: { panel != nil }, set: { if !$0 { panel = nil } })) { BrowserPanels(browser: browser, panel: panel ?? "settings").tint(accent) }
        .alert("NIVQO", isPresented: Binding(get: { browser.notice != nil }, set: { if !$0 { browser.notice = nil } })) { Button("OK") { browser.notice = nil } } message: { Text(browser.notice ?? "") }
        .sheet(isPresented: $showingFlow) { FlowView(flow: flow, browser: browser) }
        .sheet(isPresented: $showingTabs) {
            NavigationStack {
                List {
                    Section {
                        Button { showingTabs = false; panel = "spaces" } label: {
                            Label("\(browser.activeSpace.name) Space · Change Space", systemImage: "square.grid.2x2")
                        }
                    }
                    ForEach(browser.visibleTabs) { tab in
                        HStack {
                            Button {
                                browser.select(tab); showingTabs = false
                            } label: {
                                Label(tab.title, systemImage: tab.isPrivate ? "eye.slash" : "globe").lineLimit(2)
                            }
                            Spacer()
                            Button { browser.close(tab.id) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).accessibilityLabel("Close \(tab.title)")
                        }.padding(.vertical, 8)
                    }
                }.navigationTitle("Your tabs")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) { Button("Done") { showingTabs = false } }
                        ToolbarItem(placement: .navigationBarTrailing) { Button("New tab") { browser.newTab(); showingTabs = false } }
                    }
            }
        }
        .sheet(isPresented: $showingBookmarks) {
            NavigationStack {
                List {
                    if browser.visibleBookmarks.isEmpty { Text("Save a page from the browser menu to find it here.").foregroundStyle(.secondary) }
                    ForEach(browser.visibleBookmarks) { bookmark in
                        Button {
                            if let url = safeWebURL(bookmark.url) { browser.selected.load(url) }
                            showingBookmarks = false
                        } label: {
                            VStack(alignment: .leading, spacing: 6) { Text(bookmark.title).foregroundStyle(.primary); Text(bookmark.url).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    }.onDelete(perform: browser.removeBookmarks)
                }.navigationTitle("Bookmarks").toolbar { Button("Done") { showingBookmarks = false } }
            }
        }
        .confirmationDialog("Clear cookies, caches and website data, and close all tabs? Bookmarks will remain.", isPresented: $clearConfirmation, titleVisibility: .visible) {
            Button("Clear website data", role: .destructive) { browser.clearWebsiteData() }
        }
    }
    private var spaceAccent: some View {
        Rectangle().fill(accent).frame(height: 3)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct BrowserPage: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var browser: BrowserModel
    let openFlow: () -> Void
    let openPanel: (String) -> Void
    let openTabs: () -> Void
    let openBookmarks: () -> Void
    let clearData: () -> Void
    @State private var address = ""
    @State private var editingAddress = false
    @FocusState private var addressFocused: Bool
    @State private var editingCurrentURL = false
    @State private var websiteKeyboardVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var accent: Color { Color(spaceHex: browser.activeSpace.hex) }
    private var isHome: Bool { tab.url.flatMap { safeWebURL($0.absoluteString) } == nil }
    private var compact: Bool {
        tab.hidesChrome && !isHome && !editingAddress && !websiteKeyboardVisible && !voiceOver
    }
    private var suggestions: [SearchHistoryItem] {
        editingCurrentURL ? [] : browser.recentSearches(matching: address, in: tab)
    }
    private var domain: String { tab.url?.host ?? "Search or enter a website" }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if isHome { homePage }
                else { WebPage(webView: tab.webView).id(tab.id) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 6) {
                    if let notice = tab.recoveryNotice { recoveryBanner(notice) }
                    if editingAddress {
                        searchSuggestions(maxHeight: min(220, max(44, geometry.size.height * 0.38)))
                        addressEditor
                    } else if compact {
                        compactDock
                    } else {
                        expandedDock(width: geometry.size.width)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 5)
                .padding(.bottom, 6)
            }
            .overlay(alignment: .top) {
                if tab.isLoading {
                    ProgressView(value: tab.progress).tint(accent).frame(height: 2)
                        .padding(.top, 3).accessibilityLabel("Page loading")
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: compact)
        .onChange(of: editingAddress) { _, editing in
            if editing { tab.setChromeHidden(false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            websiteKeyboardVisible = true
            tab.setChromeHidden(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            websiteKeyboardVisible = false
        }
        .alert("NIVQO", isPresented: Binding(get: { tab.message != nil }, set: { if !$0 { tab.message = nil } })) {
            Button("OK") { tab.message = nil }
        } message: { Text(tab.message ?? "") }
    }

    private func beginSearch() {
        address = ""
        editingCurrentURL = false
        editingAddress = true
        tab.setChromeHidden(false)
    }
    private func endSearch() {
        addressFocused = false
        editingAddress = false
        editingCurrentURL = false
    }
    private func runSearch(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        browser.search(query)
        endSearch()
    }

    private var addressPill: some View {
        Button(action: beginSearch) {
            HStack(spacing: 7) {
                Image(systemName: tab.isPrivate ? "eye.slash" : (isHome ? "magnifyingglass" : "globe"))
                    .foregroundStyle(accent).font(.footnote)
                Text(domain).font(.subheadline).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(Color.nivqoPanel, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isHome ? "Search or enter a website" : "Search or edit address, \(domain)")
        .accessibilityIdentifier("addressPill")
    }

    @ViewBuilder private func expandedDock(width: CGFloat) -> some View {
        // Keep all six controls usable at 320 pt and at larger text sizes.
        // Wide iPhones in landscape can use the complete single-row layout.
        VStack(spacing: 2) {
            if width >= 360 && !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 4) {
                    backButton
                    addressPill
                    flowButton
                    spacesButton
                    tabsButton
                    browserMenu
                }
            } else {
                HStack(spacing: 4) {
                    backButton
                    addressPill
                }
                HStack(spacing: 0) {
                    flowButton.frame(maxWidth: .infinity)
                    spacesButton.frame(maxWidth: .infinity)
                    tabsButton.frame(maxWidth: .infinity)
                    browserMenu.frame(maxWidth: .infinity)
                }
            }
        }
        .padding(5)
        .background(Color.nivqoPanel.opacity(0.94), in: RoundedRectangle(cornerRadius: 27))
        .overlay { RoundedRectangle(cornerRadius: 27).strokeBorder(.white.opacity(0.09)) }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var compactDock: some View {
        HStack(spacing: 4) {
            Button { tab.setChromeHidden(false) } label: {
                HStack(spacing: 8) {
                    Image(systemName: tab.isPrivate ? "eye.slash" : "chevron.up").foregroundStyle(accent)
                    Text(domain).lineLimit(1).truncationMode(.middle).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.footnote).padding(.horizontal, 12).frame(minHeight: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show browser controls, \(domain)")
            .accessibilityIdentifier("showBrowserControls")
            flowButton
            spacesButton
        }
        .padding(.horizontal, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var backButton: some View {
        Button { tab.goBack() } label: { controlIcon("chevron.left") }
            .disabled(!tab.canGoBack).accessibilityLabel("Back")
    }
    private var flowButton: some View {
        Button(action: openFlow) { controlIcon("link") }
            .accessibilityLabel("Flow and Drop").accessibilityIdentifier("flowButton")
    }
    private var spacesButton: some View {
        Button { openPanel("spaces") } label: { controlIcon("square.3.layers.3d") }
            .accessibilityLabel("Spaces, \(browser.activeSpace.name)").accessibilityIdentifier("spacesButton")
    }
    private var tabsButton: some View {
        Button(action: openTabs) {
            Text(String(browser.visibleTabs.count)).font(.caption.bold())
                .frame(minWidth: 23, minHeight: 23)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(lineWidth: 1.5))
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("\(browser.visibleTabs.count) tabs").accessibilityIdentifier("tabsButton")
    }
    private func controlIcon(_ name: String) -> some View {
        Image(systemName: name).font(.title3)
            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
    private var browserMenu: some View {
        Menu {
            Button("Forward", systemImage: "chevron.right") { tab.goForward() }.disabled(!tab.canGoForward)
            Button(tab.isLoading ? "Stop loading" : "Reload page", systemImage: tab.isLoading ? "xmark" : "arrow.clockwise") {
                if tab.isLoading { tab.stopLoading() } else { tab.retryPage() }
            }.disabled(isHome)
            Button("New tab", systemImage: "plus") { browser.newTab() }
            Button("New private tab", systemImage: "eye.slash") { browser.newTab(privateMode: true) }
            Button("Save bookmark", systemImage: "bookmark") { browser.bookmarkCurrent() }.disabled(isHome || tab.isPrivate)
            Button("Bookmarks", systemImage: "book", action: openBookmarks)
            Button("History", systemImage: "clock") { openPanel("history") }
            Button("Import & saved accounts", systemImage: "square.and.arrow.down") { openPanel("imports") }
            Button("Shield & privacy", systemImage: "shield") { openPanel("privacy") }
            Button("Assist · read page", systemImage: "sparkles") { openPanel("assist") }
            Button("Settings & updates", systemImage: "gearshape") { openPanel("settings") }
            if !isHome, let url = tab.url {
                ShareLink(item: url) { Label("Share page", systemImage: "square.and.arrow.up") }
                Link(destination: url) { Label("Open in default browser", systemImage: "safari") }
                Button("Hide browser controls", systemImage: "chevron.down") { tab.setChromeHidden(true) }
            }
            Button("Clear website data", systemImage: "trash", role: .destructive, action: clearData)
        } label: { controlIcon("ellipsis.circle") }
        .accessibilityLabel("Browser menu").accessibilityIdentifier("browserMenu")
    }

    private var addressEditor: some View {
        HStack(spacing: 4) {
            TextField("Search or enter a website", text: $address)
                .keyboardType(.webSearch).textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.go).focused($addressFocused)
                .onSubmit { runSearch(address) }
                .padding(.leading, 12).frame(minHeight: 44)
                .accessibilityLabel("Website address or search").accessibilityIdentifier("addressEditor")
                .task { addressFocused = true }
            if !address.isEmpty {
                Button { address = ""; editingCurrentURL = false } label: { controlIcon("xmark.circle.fill") }
                    .accessibilityLabel("Clear address")
            }
            Button("Cancel", action: endSearch).font(.callout)
                .frame(minWidth: 44, minHeight: 44).padding(.trailing, 8)
        }
        .padding(5).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 27))
    }

    @ViewBuilder private func searchSuggestions(maxHeight: CGFloat) -> some View {
        if !suggestions.isEmpty || (!isHome && !editingCurrentURL) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !suggestions.isEmpty {
                        Text(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Recent searches" : "Previous searches")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                        ForEach(suggestions) { item in
                            Button { runSearch(item.query) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(accent)
                                    Text(item.query).foregroundStyle(.primary).lineLimit(2)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).accessibilityLabel("Search again for \(item.query)")
                        }
                    }
                    // Editing the current URL remains available in private tabs
                    // and when saved history is disabled. It never autocompletes.
                    if !isHome, let url = tab.url, !editingCurrentURL {
                        Button {
                            editingCurrentURL = true
                            address = url.absoluteString
                            addressFocused = true
                        } label: {
                            Label("Edit current website address", systemImage: "link")
                                .font(.callout).padding(.horizontal, 14).padding(.vertical, 8)
                                .frame(minHeight: 44)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: maxHeight)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func recoveryBanner(_ notice: String) -> some View {
        HStack(spacing: 8) {
            Text(notice).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            Button("Reload") { tab.retryPage() }.frame(minWidth: 44, minHeight: 44)
            Button { tab.dismissRecoveryNotice() } label: { controlIcon("xmark") }.accessibilityLabel("Dismiss page notice")
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("recoveryNotice")
    }

    private var homePage: some View {
        ZStack {
            Color.nivqoBackground.ignoresSafeArea()
            RadialGradient(colors: [Color(red: 0.015, green: 0.23, blue: 0.38).opacity(0.8),
                                    Color.nivqoBackground],
                           center: .top, startRadius: 10, endRadius: 480)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        Image("Brand").resizable().scaledToFit()
                            .frame(width: 98, height: 98)
                            .accessibilityLabel("NIVQO logo")
                        Text("N I V Q O").font(.system(size: 30, weight: .bold, design: .rounded))
                            .tracking(4)
                        Text("The web, on your terms.").font(.subheadline.weight(.medium))
                            .foregroundStyle(accent)
                        Text(tab.isPrivate ? "PRIVATE SESSION · HISTORY OFF" : "THE WEB. YOUR WAY.")
                            .font(.caption2.weight(.semibold)).tracking(2.1)
                            .foregroundStyle(.secondary)
                    }.padding(.top, 28)
                    Button(action: beginSearch) {
                        HStack(spacing: 11) {
                            Image(systemName: "magnifyingglass").foregroundStyle(accent)
                            Text("Search or enter a website").foregroundStyle(.secondary)
                                .font(.subheadline)
                            Spacer()
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .foregroundStyle(accent)
                        }
                        .padding(.horizontal, 16).frame(minHeight: 52)
                        .background(Color.nivqoPanel, in: Capsule())
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("homeSearch")
                    shortcutsGrid
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            Text("Explore NIVQO").font(.headline)
                            Spacer()
                            HStack(spacing: 5) {
                                Circle().fill(accent).frame(width: 7, height: 7)
                                Text(browser.activeSpace.name).font(.caption.bold())
                                    .foregroundStyle(accent)
                            }
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            feature("Flow + Drop", "Move tabs & files", "link", openFlow)
                            feature("Spaces", "Separate identities", "square.3.layers.3d") { openPanel("spaces") }
                            feature("Shield", "Privacy controls", "shield") { openPanel("privacy") }
                            feature("Assist", "Local reading tools", "sparkles") { openPanel("assist") }
                        }
                    }
                    Button { openPanel("imports") } label: {
                        Label("Import bookmarks & saved accounts", systemImage: "square.and.arrow.down")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 24).padding(.bottom, 36)
                    .frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
        }
    }

    private var shortcutsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 16) {
            siteShortcut("Google", "g.circle.fill", "https://www.google.com", .white)
            siteShortcut("YouTube", "play.rectangle.fill", "https://www.youtube.com", .red)
            siteShortcut("Amazon", "a.circle.fill", "https://www.amazon.co.uk", .orange)
            siteShortcut("BBC", "tv", "https://www.bbc.co.uk", .white)
            siteShortcut("Wikipedia", "book.closed.fill", "https://www.wikipedia.org", .white)
            siteShortcut("Sky News", "newspaper.fill", "https://news.sky.com", .red)
            siteShortcut("GitHub", "chevron.left.forwardslash.chevron.right", "https://github.com", .white)
            Button(action: openBookmarks) { shortcutContents("Saved", symbol: "plus", tint: accent) }
                .buttonStyle(.plain).accessibilityLabel("Open bookmarks")
        }
    }

    private func siteShortcut(_ name: String, _ symbol: String, _ url: String, _ tint: Color) -> some View {
        Button {
            guard let page = safeWebURL(url) else { return }
            endSearch()
            tab.load(page)
        } label: { shortcutContents(name, symbol: symbol, tint: tint) }
        .buttonStyle(.plain).accessibilityLabel("Open \(name)")
    }

    private func shortcutContents(_ name: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol).font(.title3.weight(.semibold))
                .foregroundStyle(tint).frame(maxWidth: .infinity).frame(height: 55)
                .background(Color.nivqoPanel, in: RoundedRectangle(cornerRadius: 15))
            Text(name).font(.caption2).foregroundStyle(.primary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity)
    }

    private func feature(_ title: String, _ detail: String, _ symbol: String,
                         _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title2).foregroundStyle(accent)
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, minHeight: 112).padding(8)
                .background(Color.nivqoPanel, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(accent.opacity(0.13)))
        }.buttonStyle(.plain)
    }
}

extension Color {
    init(spaceHex: String) {
        let value = UInt32(spaceHex, radix: 16) ?? 0x27c9ff
        self.init(red: Double((value >> 16) & 255)/255, green: Double((value >> 8) & 255)/255, blue: Double(value & 255)/255)
    }
}

private struct WebPage: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
