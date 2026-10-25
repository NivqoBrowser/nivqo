import SwiftUI
import UniformTypeIdentifiers

struct BrowserPanels: View {
    @ObservedObject var browser: BrowserModel
    let panel: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var name = ""
    @State private var editingSpace: BrowserSpace?
    @State private var deletingSpace: BrowserSpace?
    @State private var editedName = ""
    @State private var picker = false
    @State private var passwords = false
    @State private var preview: BrowserImport?
    @State private var message: String?
    @State private var reading = ""
    @State private var readingBusy = false
    @State private var clear = false
    @State private var removeAccount: SavedAccount?
    private var title: String {
        ["spaces":"Spaces", "history":"History", "imports":"Import & accounts", "privacy":"Shield & privacy", "assist":"Assist", "settings":"Settings & updates"][panel] ?? "NIVQO"
    }
    var body: some View {
        NavigationStack {
            List {
                Section { Label(browser.activeSpace.name + " Space", systemImage: "circle.fill").foregroundStyle(Color(spaceHex: browser.activeSpace.hex)) }
                if panel == "spaces" { spaces }
                else if panel == "imports" { imports }
                else if panel == "history" { history }
                else if panel == "assist" { assist }
                else if panel == "privacy" { privacy }
                else { settings }
            }
            .scrollContentBackground(.hidden).background(Color.nivqoBackground)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { preview = nil; dismiss() } } }
            .fileImporter(isPresented: $picker, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
                    let data = try file.read(upToCount: ImportParser.limit + 1) ?? Data()
                    preview = try ImportParser.parse(data, passwords: passwords, spaceID: browser.activeSpaceID)
                } catch { if (error as NSError).code != NSUserCancelledError { message = error.localizedDescription } }
            }
            .onChange(of: scenePhase) { phase in if phase == .background { preview = nil; reading = "" } }
            .alert("NIVQO", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
            .confirmationDialog("Clear website data and close all tabs in every Space? Saved accounts and bookmarks remain.", isPresented: $clear, titleVisibility: .visible) { Button("Clear website data", role: .destructive) { browser.clearWebsiteData() } }
            .alert("Rename Space", isPresented: Binding(
                get: { editingSpace != nil },
                set: { if !$0 { editingSpace = nil } }
            )) {
                TextField("Space name", text: $editedName)
                Button("Save") {
                    if let space = editingSpace { browser.renameSpace(space.id, to: editedName) }
                    editingSpace = nil
                }
                Button("Cancel", role: .cancel) { editingSpace = nil }
            } message: {
                Text("Names can be up to 32 characters. Tabs and saved data stay in this Space.")
            }
            .confirmationDialog("Delete \(deletingSpace?.name ?? "Space")?", isPresented: Binding(
                get: { deletingSpace != nil },
                set: { if !$0 { deletingSpace = nil } }
            ), titleVisibility: .visible) {
                Button("Delete Space and its data", role: .destructive) {
                    if let space = deletingSpace { perform { try browser.deleteSpace(space.id) } }
                    deletingSpace = nil
                }
                Button("Cancel", role: .cancel) { deletingSpace = nil }
            } message: {
                Text("This deletes that Space's tabs, bookmarks, history, saved accounts and website data. Other Spaces are unaffected. This cannot be undone.")
            }
            .confirmationDialog("Remove this saved account from NIVQO?", isPresented: Binding(get: { removeAccount != nil }, set: { if !$0 { removeAccount = nil } }), titleVisibility: .visible) {
                Button("Remove account", role: .destructive) { if let account = removeAccount { perform { try browser.deleteAccount(account.id) } }; removeAccount = nil }
            }
        }
    }
    private var spaces: some View {
        Group {
            Section("Your Spaces") {
                ForEach(browser.spaces) { space in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Button {
                                browser.switchSpace(space.id)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: space.id == "work" ? "briefcase.fill" :
                                            space.id == "gaming" ? "gamecontroller.fill" :
                                            space.id == "shopping" ? "bag.fill" : "person.fill")
                                        .foregroundStyle(Color(spaceHex: space.hex))
                                        .frame(width: 42, height: 42)
                                        .background(Color(spaceHex: space.hex).opacity(0.16),
                                                    in: RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(space.name).font(.headline).foregroundStyle(.primary)
                                        Text("\(browser.tabs.filter { $0.spaceID == space.id }.count) tabs · \(browser.bookmarks.filter { ($0.spaceID ?? "personal") == space.id }.count) bookmarks")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if space.id == browser.activeSpaceID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color(spaceHex: space.hex))
                                    }
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("Open \(space.name) Space")
                            Menu {
                                Button("Rename", systemImage: "pencil") {
                                    editedName = space.name
                                    editingSpace = space
                                }
                                if space.id != "personal" {
                                    Button("Delete Space", systemImage: "trash", role: .destructive) {
                                        deletingSpace = space
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title3).frame(width: 44, height: 44)
                            }.accessibilityLabel("Manage \(space.name) Space")
                        }
                        HStack(spacing: 9) {
                            Text("Colour").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            ForEach(SpacePalette.choices, id: \.hex) { choice in
                                let used = browser.spaces.contains { $0.id != space.id && $0.hex == choice.hex }
                                Button { browser.recolorSpace(space.id, to: choice.hex) } label: {
                                    Circle().fill(Color(spaceHex: choice.hex))
                                        .frame(width: 20, height: 20)
                                        .overlay {
                                            Circle().strokeBorder(space.hex == choice.hex ? Color.white : Color.clear, lineWidth: 2)
                                        }
                                        .frame(width: 25, height: 34)
                                        .opacity(used ? 0.28 : 1)
                                }
                                .disabled(used)
                                .accessibilityLabel("\(choice.name) for \(space.name)")
                            }
                        }
                    }
                    .padding(.vertical, 7)
                }
            }
            Section("Add a Space") {
                TextField("Name, e.g. Travel", text: $name)
                Button("Create Space") { browser.addSpace(name); name = "" }
            }
            Section {
                Text("Rename or recolour a Space without changing its browsing data. Personal is the permanent base Space; all other Spaces can be deleted with confirmation. Each Space keeps separate cookies, history and bookmarks.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    private var imports: some View {
        Group {
            Section("Import from another browser") {
                Text("Export bookmarks as HTML or Chromium JSON, or saved passwords as CSV from Brave, Vivaldi, Chrome or Edge. Choose the exported file in Files. Imports stay in this Space.").font(.subheadline)
                Button("Choose bookmarks export") { preview = nil; passwords = false; picker = true }
                Button("Choose passwords CSV") { preview = nil; passwords = true; picker = true }
                Text("Password exports contain readable passwords. Remove the export from Files after importing. Existing website sessions, passkeys and browser sync accounts are not imported.").font(.footnote).foregroundStyle(.secondary)
            }
            if let p = preview {
                Section("Review before importing") {
                    Text("\(p.rows.count) valid entries · \(p.skipped) skipped. Duplicates will be ignored; limits are 1,000 bookmarks and 5,000 accounts.")
                    ForEach(Array(p.rows.prefix(3).enumerated()), id: \.offset) { _, row in VStack(alignment: .leading, spacing: 5) { Text(row.title); Text(row.url).font(.caption).foregroundStyle(.secondary).lineLimit(2); if p.passwords { Text(row.username).font(.caption) } } }
                    Button("Import into \(browser.spaces.first { $0.id == p.spaceID }?.name ?? "Space")") {
                        perform { let count = try browser.commitImport(p); preview = nil; message = "Imported \(count) new entries." }
                    }.buttonStyle(.borderedProminent)
                    Button("Cancel preview", role: .cancel) { preview = nil }
                }
            }
            Section("Saved accounts") {
                if browser.visibleAccounts.isEmpty { Text("No saved accounts in this Space.").foregroundStyle(.secondary) }
                ForEach(browser.visibleAccounts) { account in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(account.title).font(.headline); Text(account.url).font(.caption).foregroundStyle(.secondary).lineLimit(2); Text(account.username).font(.subheadline)
                        HStack {
                            Button("Copy username") { perform { try browser.copyAccount(account.id, password: false); message = browser.notice; browser.notice = nil } }
                            Button("Copy password") { perform { try browser.copyAccount(account.id, password: true); message = browser.notice; browser.notice = nil } }
                        }.buttonStyle(.bordered).font(.caption)
                        Button("Open website") { if let url = safeWebURL(account.url) { browser.selected.load(url); dismiss() } }
                        Button("Remove", role: .destructive) { removeAccount = account }
                    }.padding(.vertical, 8)
                }
                Text("Passwords are stored in this iPhone’s Keychain. Copy explicitly to paste into a sign-in form; clipboard contents expire after 30 seconds. System-wide AutoFill is not included.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    private var history: some View {
        Group {
            Section("Search history") {
                if browser.visibleSearchHistory.isEmpty {
                    Text("No saved searches in this Space.").foregroundStyle(.secondary)
                }
                ForEach(browser.visibleSearchHistory) { item in
                    Button { browser.search(item.query); dismiss() } label: {
                        Label(item.query, systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.primary)
                    }
                }
            }
            Section("Websites visited") {
                if browser.visibleHistory.isEmpty { Text("No history in this Space.").foregroundStyle(.secondary) }
                ForEach(browser.visibleHistory) { item in
                    Button { if let url = safeWebURL(item.url) { browser.selected.load(url); dismiss() } } label: {
                        VStack(alignment: .leading, spacing: 6) { Text(item.title).foregroundStyle(.primary); Text(item.url).font(.caption).foregroundStyle(.secondary).lineLimit(1); Text(item.date, style: .date).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
            Section { Button("Clear search and browsing history for this Space", role: .destructive) { browser.clearHistory() } }
        }
    }
    private var privacy: some View {
        Group {
            Section("Website sessions") {
                Text("Each Space has its own WebKit website storage. HTTPS encrypts connections to sites that support it. Private tabs use temporary storage and do not add history or bookmarks.")
                Toggle("Save browsing history", isOn: $browser.saveHistory)
                Button("Open a private tab") { browser.newTab(privateMode: true); dismiss() }
            }
            Section("Tracker protection") {
                Text("This release uses WebKit’s built-in privacy protections. The desktop tracker-filter engine is not included on iPhone yet; this panel does not claim to block every tracker.").font(.subheadline)
            }
            Section { Button("Clear website data in all Spaces", role: .destructive) { clear = true } }
        }
    }
    private var assist: some View {
        Group {
            Section("Read this page") {
                Text("Extract readable text from the current page on this device. Nothing is sent to an AI service. This is a reading tool, not an AI summary.").font(.subheadline)
                Button(readingBusy ? "Reading…" : "Extract page text") {
                    readingBusy = true
                    browser.selected.webView.evaluateJavaScript("(document.querySelector('article') || document.querySelector('main') || document.body)?.innerText?.slice(0,50000) || ''") { value, error in
                        readingBusy = false
                        if let error = error { message = error.localizedDescription } else { reading = value as? String ?? ""; if reading.isEmpty { message = "No readable text found. Try another page." } }
                    }
                }.disabled(browser.selected.url == nil || readingBusy)
                if !reading.isEmpty { Text(reading).textSelection(.enabled) }
            }
        }
    }
    private var settings: some View {
        Group {
            Section("Browsing") {
                Picker("Search engine", selection: $browser.searchEngine) { ForEach(["DuckDuckGo", "Brave", "Google"], id: \.self) { Text($0) } }
                Toggle("Save browsing history", isOn: $browser.saveHistory)
                Text("Saved searches and visited websites stay on this iPhone, separated by Space. Private tabs never save either kind of history. Normal tabs can be restored after closing the app; private tabs are not restored.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Manual updates") {
                Text("NIVQO \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.9.0") · iPhone")
                Text("Install a newer IPA in Sideloadly using the same Apple account and bundle ID. Keep the existing app installed to preserve its data. Free signing needs periodic renewal.").font(.subheadline)
                Link("Open NIVQO builds", destination: URL(string: "https://github.com/NivqoBrowser/nivqo/actions")!)
            }
            Section { Button("Clear website data", role: .destructive) { clear = true } }
        }
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { message = error.localizedDescription } }
}
