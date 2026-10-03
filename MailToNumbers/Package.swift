// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "MailToNumbers",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "MailNumbersCore", targets: ["MailNumbersCore"]),
        .library(name: "SchoologyGrades", targets: ["SchoologyGrades"]),
        .library(name: "EtradeDividends", targets: ["EtradeDividends"]),
        .executable(name: "mail-to-numbers", targets: ["MailToNumbersCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(name: "MailNumbersCore"),
        .target(
            name: "SchoologyGrades",
            dependencies: ["MailNumbersCore", "SwiftSoup"]
        ),
        .target(
            name: "EtradeDividends",
            dependencies: ["MailNumbersCore", "SwiftSoup"]
        ),
        .executableTarget(
            name: "MailToNumbersCLI",
            dependencies: ["MailNumbersCore", "SchoologyGrades", "EtradeDividends"]
        ),
        .testTarget(
            name: "MailToNumbersTests",
            dependencies: ["MailNumbersCore", "SchoologyGrades", "EtradeDividends", "MailToNumbersCLI"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
