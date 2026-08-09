// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ScreenFlowLite",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ScreenFlowLite",
            path: "Sources/ScreenFlowLite",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
