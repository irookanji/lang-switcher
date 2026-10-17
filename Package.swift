// swift-tools-version:5.4
import PackageDescription

let package = Package(
    name: "LangSwitcher",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "LangSwitcher", targets: ["LangSwitcher"])
    ],
    targets: [
        .target(
            name: "LangSwitcherCore",
            linkerSettings: [
                .linkedFramework("Carbon")
            ]
        ),
        .target(
            name: "LangSwitcher",
            dependencies: ["LangSwitcherCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon")
            ]
        ),
        .target(
            name: "LangSwitcherChecks",
            dependencies: ["LangSwitcherCore"],
            path: "Tests/LangSwitcherChecks"
        )
    ]
)
