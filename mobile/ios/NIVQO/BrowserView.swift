import SwiftUI
import WebKit
import UIKit

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
        .fullScreenCover(isPresented: $showingTabs) {
            NIVQOTabOverview(browser: browser, isPresented: $showingTabs)
                .preferredColorScheme(.dark)
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
    private var isHome: Bool { tab.showsHome }
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
                if editingAddress { searchMode }
                else if isHome { homePage }
                else { WebPage(webView: tab.webView).id(tab.id) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !editingAddress {
                    VStack(spacing: 6) {
                        if let notice = tab.recoveryNotice { recoveryBanner(notice) }
                        if compact { compactDock }
                        else { expandedDock(width: geometry.size.width) }
                    }
                    .padding(.horizontal, 8).padding(.top, 5).padding(.bottom, 6)
                }
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
            if editing { tab.setChromeHidden(false); addressFocused = true }
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
        // Give URL addresses enough width; homepage already has a search field.
        VStack(spacing: 5) {
            if !isHome {
                HStack(spacing: 5) {
                    backButton
                    forwardButton
                    addressPill
                }
            }
            HStack(spacing: 0) {
                if isHome {
                    backButton.frame(maxWidth: .infinity)
                    forwardButton.frame(maxWidth: .infinity)
                }
                flowButton.frame(maxWidth: .infinity)
                spacesButton.frame(maxWidth: .infinity)
                tabsButton.frame(maxWidth: .infinity)
                browserMenu.frame(maxWidth: .infinity)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(accent.opacity(0.22), lineWidth: 0.8) }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var compactDock: some View {
        HStack(spacing: 3) {
            backButton
            forwardButton
            Button { tab.setChromeHidden(false) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.up").foregroundStyle(accent)
                    Text(domain).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.footnote)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reveal browser controls for \(domain)")
            .accessibilityIdentifier("showBrowserControls")
            flowButton
            spacesButton
        }
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(accent.opacity(0.2), lineWidth: 0.8) }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var backButton: some View {
        Button { tab.goBack() } label: { controlIcon("chevron.left") }
            .disabled(!tab.canGoBack)
            .accessibilityLabel("Back").accessibilityIdentifier("browserBackButton")
    }
    private var forwardButton: some View {
        Button { tab.goForward() } label: { controlIcon("chevron.right") }
            .disabled(!tab.canGoForward)
            .accessibilityLabel("Forward").accessibilityIdentifier("browserForwardButton")
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
            Button("NIVQO home", systemImage: "house") { tab.goHome() }.disabled(isHome)
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

    // Search terms are suggested from the current Space, never from URL visits.
    private var searchMode: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(accent)
                    TextField("Search or enter a website", text: $address)
                        .keyboardType(.webSearch).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().submitLabel(.go)
                        .focused($addressFocused)
                        .onSubmit { runSearch(address) }
                        .accessibilityIdentifier("addressEditor")
                    if !address.isEmpty {
                        Button { address = ""; editingCurrentURL = false } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 30, minHeight: 40)
                        }.accessibilityLabel("Clear search text")
                    }
                }
                .padding(.horizontal, 14).frame(minHeight: 49)
                .background(Color.nivqoPanel, in: Capsule())
                Button("Cancel", action: endSearch)
                    .font(.subheadline.weight(.medium)).frame(minHeight: 44)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !tab.isPrivate {
                        VStack(spacing: 0) {
                            HStack {
                                Text(address.isEmpty ? "Recent Searches" : "Matching Searches")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                if address.isEmpty && !browser.visibleSearchHistory.isEmpty {
                                    Button("Clear All") { browser.clearSearchHistory() }
                                        .font(.caption.weight(.medium)).foregroundStyle(accent)
                                        .accessibilityIdentifier("clearRecentSearches")
                                }
                            }.padding(.bottom, 10)
                            if suggestions.isEmpty {
                                Text(address.isEmpty ? "Searches in this Space will appear here." : "No matching previous searches.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 12)
                            }
                            ForEach(suggestions) { item in
                                HStack(spacing: 12) {
                                    Button { runSearch(item.query) } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(accent)
                                            Text(item.query).foregroundStyle(.primary).lineLimit(1)
                                            Spacer(minLength: 0)
                                        }
                                        .frame(minHeight: 49).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                    Button { browser.removeSearch(item.id) } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption).foregroundStyle(.secondary)
                                            .frame(width: 44, height: 44)
                                    }.accessibilityLabel("Remove search \(item.query)")
                                }
                                Divider().overlay(.white.opacity(0.05))
                            }
                        }
                    } else {
                        Label("Private browsing doesn't save searches.", systemImage: "eye.slash")
                            .foregroundStyle(.secondary).font(.subheadline)
                    }
                    if !isHome, let url = tab.url, !editingCurrentURL {
                        Button {
                            editingCurrentURL = true
                            address = url.absoluteString
                            addressFocused = true
                        } label: {
                            Label("Edit current website address", systemImage: "link")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 44)
                        }
                    }
                    if address.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Popular Sites").font(.subheadline.weight(.semibold))
                            shortcutsGrid
                        }
                    }
                }.padding(.horizontal, 22).padding(.top, 14)
            }.scrollDismissesKeyboard(.interactively)
        }
        .background(Color.nivqoBackground)
        .onAppear { addressFocused = true }
        .accessibilityIdentifier("nivqoSearchMode")
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
                        if tab.isPrivate {
                            Text("PRIVATE SESSION · HISTORY OFF")
                                .font(.caption2.weight(.semibold)).tracking(2.1)
                                .foregroundStyle(.secondary)
                        }
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
                }.padding(.horizontal, 24).padding(.bottom, 110)
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


private struct NIVQOTabOverview: View {
    @ObservedObject var browser: BrowserModel
    @Binding var isPresented: Bool
    @State private var showingPrivate = false
    private var accent: Color { Color(spaceHex: browser.activeSpace.hex) }
    private var filteredTabs: [BrowserTab] {
        browser.visibleTabs.filter { $0.isPrivate == showingPrivate }
    }

    // Changing the Space keeps the tab grid open, instead of forcing the user
    // to return to the webpage between Personal, Work, Gaming and Shopping.
    private func selectSpace(_ space: BrowserSpace) {
        guard space.id != browser.activeSpaceID else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            browser.switchSpace(space.id)
            showingPrivate = browser.selected.isPrivate
        }
    }

    private func moveSpace(_ direction: Int) {
        guard let index = browser.spaces.firstIndex(where: { $0.id == browser.activeSpaceID }) else { return }
        let target = index + direction
        guard browser.spaces.indices.contains(target) else { return }
        selectSpace(browser.spaces[target])
    }

    private var spaceSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(browser.spaces) { space in
                    let selected = space.id == browser.activeSpaceID
                    Button { selectSpace(space) } label: {
                        HStack(spacing: 7) {
                            Circle().fill(Color(spaceHex: space.hex)).frame(width: 9, height: 9)
                            Text(space.name)
                                .font(.subheadline.weight(selected ? .semibold : .medium))
                            Text("\(browser.tabs.filter { $0.spaceID == space.id }.count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.62))
                        }
                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.8))
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(
                            selected ? Color(spaceHex: space.hex).opacity(0.20) : Color.nivqoPanel,
                            in: Capsule()
                        )
                        .overlay {
                            Capsule().strokeBorder(
                                selected ? Color(spaceHex: space.hex) : Color.white.opacity(0.08),
                                lineWidth: selected ? 1.5 : 1
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(space.name) Space, \(browser.tabs.filter { $0.spaceID == space.id }.count) tabs")
                    .accessibilityIdentifier("spaceTab-\(space.id)")
                }
            }
            .padding(.horizontal, 18)
        }
        .accessibilityIdentifier("tabSpaceSwitcher")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                spaceSwitcher.padding(.top, 12)
                Picker("Tab type", selection: $showingPrivate) {
                    Text("Tabs").tag(false)
                    Text("Private").tag(true)
                }
                .pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 14)
                ScrollView {
                    if filteredTabs.isEmpty {
                        VStack(spacing: 15) {
                            Image(systemName: showingPrivate ? "eye.slash" : "square.on.square")
                                .font(.largeTitle).foregroundStyle(accent)
                            Text(showingPrivate ? "No private tabs" : "No open tabs")
                                .font(.headline)
                            Text(showingPrivate ? "Private tabs keep your searches out of history." : "Open a new tab to start exploring.")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .font(.subheadline)
                            Button(showingPrivate ? "New private tab" : "New tab") {
                                browser.newTab(privateMode: showingPrivate)
                                isPresented = false
                            }.buttonStyle(.borderedProminent)
                        }.padding(32).frame(maxWidth: .infinity)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                           GridItem(.flexible(), spacing: 14)], spacing: 20) {
                            ForEach(filteredTabs) { tab in
                                NIVQOTabCard(tab: tab, accent: accent,
                                    selected: tab.id == browser.selectedID,
                                    open: { browser.select(tab); isPresented = false },
                                    close: { browser.close(tab.id) })
                            }
                        }.padding(.horizontal, 18).padding(.vertical, 10)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 55).onEnded { gesture in
                        let dx = gesture.translation.width
                        let dy = gesture.translation.height
                        if abs(dx) > 85 && abs(dx) > abs(dy) * 1.5 {
                            moveSpace(dx < 0 ? 1 : -1)
                        }
                    }
                )
                HStack {
                    Menu {
                        ForEach(browser.spaces) { space in
                            Button { selectSpace(space) } label: {
                                Label(space.name, systemImage: space.id == browser.activeSpaceID ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(accent).frame(width: 8, height: 8)
                            Text(browser.activeSpace.name).font(.subheadline.weight(.medium))
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .foregroundStyle(accent)
                        .frame(minHeight: 44)
                    }
                    .accessibilityLabel("Choose browsing Space")
                    Spacer()
                    Text("\(filteredTabs.count) \(showingPrivate ? "private " : "")tabs")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Done") { isPresented = false }.foregroundStyle(accent)
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, 23).frame(minHeight: 55)
                .background(Color.nivqoPanel.opacity(0.8))
            }
            .background(Color.nivqoBackground)
            .navigationTitle("Tabs").navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        browser.newTab(privateMode: showingPrivate)
                        isPresented = false
                    } label: { Image(systemName: "plus").font(.title3) }
                        .accessibilityLabel("New tab")
                }
            }
        }
        .tint(accent)
        .onAppear { showingPrivate = browser.selected.isPrivate }
        .accessibilityIdentifier("nivqoTabOverview")
    }
}

private struct NIVQOTabCard: View {
    @ObservedObject var tab: BrowserTab
    let accent: Color
    let selected: Bool
    let open: () -> Void
    let close: () -> Void
    @State private var snapshot: UIImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topTrailing) {
                Button(action: open) {
                    ZStack {
                        Color.nivqoPanel
                        if let snapshot {
                            Image(uiImage: snapshot).resizable().scaledToFill()
                        } else {
                            VStack(spacing: 8) {
                                Image("Brand").resizable().scaledToFit()
                                    .frame(width: 55, height: 55)
                                Text(tab.url?.host ?? "NIVQO").font(.caption)
                                    .foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 205)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(selected ? accent : Color.white.opacity(0.1),
                                      lineWidth: selected ? 2 : 1))
                }.buttonStyle(.plain)
                    .accessibilityLabel("Open \(tab.title)")
                Button(action: close) {
                    Image(systemName: "xmark").font(.footnote.bold())
                        .foregroundStyle(.white).frame(width: 34, height: 34)
                        .background(Color.black.opacity(0.75), in: Circle())
                }
                .padding(7).accessibilityLabel("Close \(tab.title)")
            }
            HStack(spacing: 6) {
                Image(systemName: tab.isPrivate ? "eye.slash" : "globe").foregroundStyle(accent)
                Text(tab.title).lineLimit(1)
            }.font(.caption.weight(.medium))
        }
        .onAppear {
            guard tab.url != nil, snapshot == nil else { return }
            tab.webView.takeSnapshot(with: nil) { image, _ in
                if let image { snapshot = image }
            }
        }
        .onDisappear { snapshot = nil }
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
