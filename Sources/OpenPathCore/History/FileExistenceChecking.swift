import Foundation

/// ファイル（ディレクトリを含む）の存在確認。テストでファイルシステムを差し替えるために抽象化する。
public protocol FileExistenceChecking: Sendable {
    func fileExists(atPath path: String) -> Bool
}

/// 実ファイルシステムを参照する実装。
public struct LocalFileExistenceChecker: FileExistenceChecking {
    public init() {}

    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
