// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "EmailGobbler",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "EmailGobblerCore", targets: ["EmailGobblerCore"]),
        .library(name: "SchoologyGrades", targets: ["SchoologyGrades"]),
        .library(name: "EtradeDividends", targets: ["EtradeDividends"]),
        .library(name: "EmailGobblerService", targets: ["EmailGobblerService"]),
        .library(name: "GnuCashBook", targets: ["GnuCashBook"]),
        .library(name: "SpendingEmails", targets: ["SpendingEmails"]),
        .executable(name: "email-gobbler", targets: ["EmailGobblerCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(name: "EmailGobblerCore"),
        .target(
            name: "SchoologyGrades",
            dependencies: ["EmailGobblerCore", "SwiftSoup"]
        ),
        .target(
            name: "EtradeDividends",
            dependencies: ["EmailGobblerCore", "SwiftSoup"]
        ),
        .target(
            name: "GnuCashBook",
            dependencies: ["EmailGobblerCore"]
        ),
        .target(
            name: "SpendingEmails",
            dependencies: ["EmailGobblerCore", "GnuCashBook", "SwiftSoup"]
        ),
        .target(
            name: "EmailGobblerService",
            dependencies: ["EmailGobblerCore", "SchoologyGrades", "EtradeDividends", "GnuCashBook", "SpendingEmails"]
        ),
        .executableTarget(
            name: "EmailGobblerCLI",
            dependencies: ["EmailGobblerCore", "SchoologyGrades", "EtradeDividends"]
        ),
        .testTarget(
            name: "EmailGobblerTests",
            dependencies: ["EmailGobblerCore", "SchoologyGrades", "EtradeDividends", "GnuCashBook", "SpendingEmails", "EmailGobblerService", "EmailGobblerCLI"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
