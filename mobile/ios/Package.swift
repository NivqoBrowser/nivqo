// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "NIVQOProtocol",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "NIVQOProtocol", targets: ["NIVQOProtocol"])],
    targets: [
        .target(name: "NIVQOProtocol", path: "NIVQO", exclude: ["NIVQOApp.swift", "BrowserModel.swift", "BrowserView.swift", "BrowserPanels.swift", "FlowClient.swift", "FlowView.swift", "QRScannerView.swift", "Info.plist", "Assets.xcassets"], sources: ["FlowProtocol.swift", "BrowserData.swift", "WebContentRecoveryPolicy.swift"]),
        .testTarget(name: "NIVQOProtocolTests", dependencies: ["NIVQOProtocol"], path: "Tests", resources: [.copy("Fixtures")])
    ]
)
