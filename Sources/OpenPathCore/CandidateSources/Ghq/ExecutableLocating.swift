import Foundation

/// 検索パス（PATH と同じ `:` 区切り）から実行ファイルを探す。テストでファイルシステムを差し替えるために抽象化する。
public protocol ExecutableLocating: Sendable {
    /// 見つかった実行ファイルの絶対パス。見つからなければ nil。
    func locateExecutable(named name: String, inSearchPath searchPath: String) -> String?
}

/// 実ファイルシステムを先頭のディレクトリから順に探す実装。
///
/// 相対パスのエントリはカレントディレクトリ次第で意図しない実行ファイルを拾うため探さない。
public struct SearchPathExecutableLocator: ExecutableLocating {
    public init() {}

    public func locateExecutable(named name: String, inSearchPath searchPath: String) -> String? {
        let fileManager = FileManager.default
        for directory in ShellSearchPath.absoluteEntries(of: searchPath) {
            let candidate = directory + ShellSearchPath.pathSeparator + name
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
