import SwiftUI

@main
struct NIVQOApp: App {
    @StateObject private var browser = BrowserModel()
    @StateObject private var flow = FlowClient()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            BrowserView(browser: browser, flow: flow)
                .preferredColorScheme(.dark)
                .tint(.nivqoCyan)
                .onChange(of: scenePhase) { phase in
                    if phase == .background { browser.saveSession(); flow.disconnect() }
                }
        }
    }
}

extension Color {
    static let nivqoBackground = Color(red: 0.025, green: 0.052, blue: 0.10)
    static let nivqoPanel = Color(red: 0.07, green: 0.12, blue: 0.20)
    static let nivqoCyan = Color(red: 0.10, green: 0.79, blue: 0.96)
}
