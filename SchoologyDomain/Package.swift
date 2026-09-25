// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SchoologyDomain",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SchoologyDomain",
            targets: ["SchoologyDomain"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SchoologyDomain"
        ),
        .testTarget(
            name: "SchoologyDomainTests",
            dependencies: ["SchoologyDomain"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
