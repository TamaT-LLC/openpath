// swift-tools-version:6.0
import PackageDescription

// .app バンドル化する前（`swift run` 等）でも bundle id を持たせ、アクセシビリティ権限（TCC）が
// 実行ファイルのパスではなく bundle id で識別されるよう、Info.plist を実行ファイルの __TEXT,__info_plist に埋め込む。
// 注意: SwiftPM は Info.plist を入力ファイルとして追跡しないため、編集後は再リンク（`swift package clean` 等）が必要。
let infoPlistPath = Context.packageDirectory + "/Resources/Info.plist"

let package = Package(
    name: "openpath",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "openpath", targets: ["openpath"]),
    ],
    targets: [
        // AppKit に依存しない純 Swift 層。ユニットテストの対象。
        .target(name: "OpenPathCore"),
        // AppKit / AX 依存層。AX の C コールバックは Swift 6 の厳格な並行性チェックと相性が悪いため Swift 5 モードで扱う。
        .target(
            name: "OpenPathMac",
            dependencies: ["OpenPathCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "openpath",
            dependencies: ["OpenPathCore", "OpenPathMac"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlistPath,
                ]),
            ]
        ),
        .testTarget(
            name: "OpenPathCoreTests",
            dependencies: ["OpenPathCore"]
        ),
    ]
)
