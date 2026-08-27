// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "Qaptr",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .executable(name: "Qaptr", targets: ["Qaptr"])
  ],
  targets: [
    .executableTarget(
      name: "Qaptr",
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
    .testTarget(
      name: "QaptrTests",
      dependencies: ["Qaptr"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
  ]
)
