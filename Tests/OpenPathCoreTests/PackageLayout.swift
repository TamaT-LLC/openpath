import Foundation

/// テストからリポジトリ内のファイルを参照するためのパス解決。
/// Resources 配下はアプリのバンドル用でテストターゲットのリソースではないため、
/// このソースファイルの位置からパッケージルートを辿って参照する。
enum PackageLayout {
    static let rootDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Tests/OpenPathCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // パッケージルート

    static func url(_ relativePath: String) -> URL {
        rootDirectory.appending(path: relativePath)
    }
}
