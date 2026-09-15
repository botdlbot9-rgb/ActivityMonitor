// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "ActivityMonitor",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "ActivityMonitor", targets: ["ActivityMonitor"]),
    .library(name: "ANETelemetry", targets: ["ANETelemetry"]),
  ],
  dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")],
  targets: [
    .target(name: "SystemBridge", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOKit")]),
    .target(name: "ANETelemetry", linkerSettings: [.linkedFramework("IOKit")]),
    .executableTarget(
      name: "ActivityMonitor",
      dependencies: ["SystemBridge", "ANETelemetry", .product(name: "Sparkle", package: "Sparkle")],
      linkerSettings: [.linkedFramework("AppKit"), .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
    .testTarget(name: "ActivityMonitorTests", dependencies: ["ActivityMonitor", "ANETelemetry"]),
  ])
