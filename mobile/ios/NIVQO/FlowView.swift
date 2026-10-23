import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct TransferDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct FlowView: View {
    @ObservedObject var flow: FlowClient
    @ObservedObject var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var pairCode = ""
    @State private var note = ""
    @State private var scanner = false
    @State private var filePicker = false
    @State private var exportFile = false
    @State private var document: TransferDocument?
    @State private var filename = "Transfer.bin"
    @State private var pendingSave: IncomingTransfer?
    @State private var clipboardNotice = false
    @State private var showDeviceInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("Quick Actions").font(.headline)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            quickAction("Send Current Tab", "Send to your devices", "square.on.square") {
                                if let url = browser.selected.url {
                                    flow.sendTab(url: url, title: browser.selected.title)
                                }
                            }
                            .disabled(!flow.connected || browser.selected.isPrivate || browser.selected.url == nil || flow.sending)
                            quickAction("Send Link", "Share URL with Flow", "link") {
                                if let url = browser.selected.url { flow.sendText(url.absoluteString) }
                            }
                            .disabled(!flow.connected || browser.selected.isPrivate || browser.selected.url == nil || flow.sending)
                            quickAction("Drop Files", "Send a local file", "square.and.arrow.up") { filePicker = true }
                                .disabled(!flow.connected || flow.sending)
                            quickAction("Paired Devices", "Connection status", "desktopcomputer") {
                                showDeviceInfo = true
                            }
                        }
                    }
                    Text("Pair with a computer on the same Wi-Fi. Keep NIVQO open on both devices while transferring.")
                        .foregroundStyle(.secondary)
                    Label(flow.status, systemImage: flow.connected ? "checkmark.shield" : "link")
                        .font(.headline).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.nivqoPanel).clipShape(RoundedRectangle(cornerRadius: 14))
                    if !flow.connected {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Connect your desktop").font(.title3.bold())
                            Text("On your computer, open Flow + Drop and choose Create pairing QR.").font(.subheadline).foregroundStyle(.secondary)
                            Button { scanner = true } label: { Label("Scan desktop QR", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity).padding(8) }
                                .buttonStyle(.borderedProminent).disabled(flow.connecting)
                            Text("Or paste the pairing code").font(.subheadline.weight(.semibold))
                            TextField("nivqo-pair://…", text: $pairCode, axis: .vertical)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().lineLimit(3...5)
                                .padding(12).background(Color.nivqoBackground).clipShape(RoundedRectangle(cornerRadius: 10))
                            if let address = try? PairAddress.parse(pairCode) {
                                Text("Connect to \(address.host):\(address.port)").font(.caption).foregroundStyle(.secondary)
                            }
                            Button(flow.connecting ? "Connecting…" : "Pair with computer") { flow.join(pairCode) }
                                .buttonStyle(.borderedProminent).disabled(flow.connecting || pairCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if flow.connecting { Button("Cancel") { flow.disconnect() }.buttonStyle(.bordered) }
                        }.padding(20).background(Color.nivqoPanel).clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Flow · send a tab").font(.title3.bold())
                            Text(browser.selected.url?.absoluteString ?? "Open a website to send its tab.").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            Button("Send current tab") {
                                if let url = browser.selected.url { flow.sendTab(url: url, title: browser.selected.title) }
                            }.buttonStyle(.borderedProminent).disabled(flow.sending || browser.selected.url == nil || browser.selected.isPrivate)
                            if browser.selected.isPrivate { Text("Private tabs cannot be sent.").font(.caption).foregroundStyle(.secondary) }
                        }.padding(20).background(Color.nivqoPanel).clipShape(RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Drop · text & files").font(.title3.bold())
                            TextField("Write a note…", text: $note, axis: .vertical).lineLimit(3...6)
                                .padding(12).background(Color.nivqoBackground).clipShape(RoundedRectangle(cornerRadius: 10))
                            HStack(spacing: 14) {
                                Button("Send text") { flow.sendText(note) }.buttonStyle(.borderedProminent).disabled(flow.sending || note.isEmpty)
                                Button("Choose file") { filePicker = true }.buttonStyle(.bordered).disabled(flow.sending)
                            }
                            Text("Files up to 4 MiB. The receiving device must accept each item.").font(.caption).foregroundStyle(.secondary)
                        }.padding(20).background(Color.nivqoPanel).clipShape(RoundedRectangle(cornerRadius: 18))
                        Button("Disconnect device", role: .destructive) { flow.disconnect() }.buttonStyle(.bordered)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Incoming transfers").font(.title3.bold())
                        if flow.incoming.isEmpty { Text("Nothing waiting. Incoming tabs and files require your approval.").foregroundStyle(.secondary).padding(.vertical, 20) }
                        ForEach(flow.incoming) { item in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(item.title).font(.headline)
                                Text(item.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(5)
                                HStack(spacing: 16) {
                                    Button(acceptLabel(item)) { accept(item) }.buttonStyle(.borderedProminent)
                                    Button("Decline", role: .destructive) { flow.dismiss(item) }.buttonStyle(.bordered)
                                }
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.nivqoBackground).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }.padding(20).background(Color.nivqoPanel).clipShape(RoundedRectangle(cornerRadius: 18))
                    Text("Encrypted direct transfers using the desktop Flow protocol. No cloud relay. This alpha transport has not been independently audited; protect pairing codes and use a trusted local network.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }.background(Color.nivqoBackground).navigationTitle("Flow + Drop")
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $scanner) {
                    NavigationStack {
                        QRScannerView { result in
                            scanner = false
                            switch result {
                            case .success(let code):
                                do { _ = try PairAddress.parse(code); pairCode = code }
                                catch { flow.errorMessage = error.localizedDescription }
                            case .failure(let error): flow.errorMessage = error.localizedDescription
                            }
                        }.ignoresSafeArea(edges: .bottom).navigationTitle("Scan desktop QR")
                            .toolbar { Button("Cancel") { scanner = false } }
                    }
                }
                .fileImporter(isPresented: $filePicker, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                    do {
                        guard let url = try result.get().first else { return }
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let handle = try FileHandle(forReadingFrom: url)
                        defer { try? handle.close() }
                        let data = try handle.read(upToCount: FlowProtocol.maximumFile + 1) ?? Data()
                        guard data.count <= FlowProtocol.maximumFile else { throw FlowError.invalid("Choose a file up to 4 MiB.") }
                        flow.sendFile(name: url.lastPathComponent, bytes: data)
                    } catch { flow.errorMessage = error.localizedDescription }
                }
                .fileExporter(isPresented: $exportFile, document: document, contentType: .data, defaultFilename: filename) { result in
                    switch result {
                    case .success: if let item = pendingSave { flow.dismiss(item) }
                    case .failure(let error): flow.errorMessage = error.localizedDescription
                    }
                    pendingSave = nil; document = nil
                }
                .alert("Flow + Drop", isPresented: Binding(get: { flow.errorMessage != nil }, set: { if !$0 { flow.errorMessage = nil } })) {
                    Button("OK") { flow.errorMessage = nil }
                } message: { Text(flow.errorMessage ?? "") }
                .alert("Text copied", isPresented: $clipboardNotice) { Button("OK", role: .cancel) {} } message: { Text("The copied text expires in two minutes and stays on this device’s clipboard.") }
                .alert("Paired devices", isPresented: $showDeviceInfo) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(flow.status + ". Pair a desktop on the same Wi-Fi before sending.")
                }
        }
    }
    private func quickAction(_ title: String, _ subtitle: String, _ icon: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.title2).foregroundStyle(Color.nivqoCyan)
                Text(title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary).multilineTextAlignment(.leading)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .padding(13)
            .background(Color.nivqoPanel, in: RoundedRectangle(cornerRadius: 15))
        }.buttonStyle(.plain)
    }
    private func acceptLabel(_ item: IncomingTransfer) -> String {
        switch item.content { case .tab: return "Open tab"; case .text: return "Copy text"; case .file: return "Save file" }
    }
    private func accept(_ item: IncomingTransfer) {
        guard Date().timeIntervalSince(item.receivedAt) <= 600 else { flow.dismiss(item); flow.errorMessage = "This transfer expired. Send it again."; return }
        switch item.content {
        case .tab(let url, _): browser.newTab(url: url); flow.dismiss(item); dismiss()
        case .text(let text):
            UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: text]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
            flow.dismiss(item); clipboardNotice = true
        case .file(let name, let data): filename = name; document = TransferDocument(data: data); pendingSave = item; exportFile = true
        }
    }
}
