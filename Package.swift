// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "cordova-sentry",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "cordova-sentry",
            targets: ["CordovaSentry"]
        )
    ],
    dependencies: [
        // cordova-ios rewrites this dependency to a local relative path during build
        .package(url: "https://github.com/apache/cordova-ios.git", branch: "master"),
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", from: "9.19.1")
    ],
    targets: [
        .target(
            name: "CordovaSentry",
            dependencies: [
                .product(name: "Cordova", package: "cordova-ios"),
                .product(name: "Sentry", package: "sentry-cocoa")
            ],
            path: "src/ios",
            sources: ["SentryCordova.swift"]
        )
    ]
)
