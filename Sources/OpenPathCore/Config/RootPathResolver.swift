/// config.toml の `roots` に書かれたパスを、正規化した絶対パスへ解決する。
///
/// `~` / `~/...` をホームディレクトリで展開し、空要素・`.`・`..`・末尾の `/` を字句的に正規化する。
/// 純粋な文字列処理にするためファイルシステムは参照せず、シンボリックリンクも解決しない。
public struct RootPathResolver: Sendable {
    private static let separator = "/"
    private static let homeDirectoryPrefix = "~"
    private static let currentDirectory = "."
    private static let parentDirectory = ".."

    private let homeDirectory: String

    /// - Parameter homeDirectory: `~` の展開先。テストでは任意のパスを注入する
    public init(homeDirectory: String) {
        self.homeDirectory = homeDirectory
    }

    /// 絶対パスに解決できなければ nil（相対パス、`~user` 形式など）
    public func resolve(_ path: String) -> String? {
        guard let expanded = expandingHomeDirectory(in: path), expanded.hasPrefix(Self.separator) else {
            return nil
        }
        return Self.normalize(absolutePath: expanded)
    }

    private func expandingHomeDirectory(in path: String) -> String? {
        guard path.hasPrefix(Self.homeDirectoryPrefix) else { return path }
        let rest = path.dropFirst(Self.homeDirectoryPrefix.count)
        // `~user` は他ユーザーのホームを指すが、Core からはユーザーデータベースを引かないため扱わない
        guard rest.isEmpty || rest.hasPrefix(Self.separator) else { return nil }
        return homeDirectory + rest
    }

    private static func normalize(absolutePath: String) -> String {
        var components: [Substring] = []
        for component in absolutePath.split(separator: separator) {
            switch component {
            case currentDirectory:
                continue
            case parentDirectory:
                // ルートより上には出ない
                _ = components.popLast()
            default:
                components.append(component)
            }
        }
        return separator + components.joined(separator: separator)
    }
}
