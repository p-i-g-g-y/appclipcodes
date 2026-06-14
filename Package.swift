// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppClipCode",
    platforms: [
        .iOS(.v13),
        .macOS(.v11),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(name: "AppClipCode", targets: ["AppClipCode"]),
    ],
    targets: [
        .target(
            name: "AppClipCode",
            resources: [
                // NB: use .process on the individual data files, not .copy on the
                // Resources directory. Copying the directory nests a Resources/
                // folder inside the resource bundle, which fails codesign on iOS
                // ("bundle format unrecognized") for both simulator and device.
                // .process flattens the files to the bundle root.
                .process("Resources/h.data"),
                .process("Resources/spq.data"),
                .process("Resources/cpq.data"),
            ]
        ),
        .testTarget(
            name: "AppClipCodeTests",
            dependencies: ["AppClipCode"],
            resources: [
                .copy("Fixtures/random_vectors.json"),
                .copy("Fixtures/comprehensive_vectors.json"),
                .copy("Fixtures/apple_comprehensive"),
            ]
        ),
    ]
)
