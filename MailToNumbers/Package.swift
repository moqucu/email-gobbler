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
        .executableTarget(
            name: "MailToNumbersCLI",
            dependencies: ["MailNumbersCore", "SchoologyGrades"]
        ),
        .testTarget(
            name: "MailToNumbersTests",
            dependencies: ["MailNumbersCore", "SchoologyGrades", "MailToNumbersCLI"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
