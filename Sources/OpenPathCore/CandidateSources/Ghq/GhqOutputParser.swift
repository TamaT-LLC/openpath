import Foundation

/// ghq の標準出力の正規化。
enum GhqOutputParser {
    private static let pathSeparator = "/"

    /// `ghq root` の出力から root を取り出す。空なら nil。
    static func root(fromOutput output: String) -> String? {
        nonEmptyLines(of: output).first
    }

    /// `ghq list -p` の出力をリポジトリの絶対パス一覧にする。
    /// 空行と前後の空白を除き、相対パスは root と結合し、重複は最初の出現を残す。
    static func repositoryPaths(fromListOutput output: String, root: String) -> [String] {
        nonEmptyLines(of: output)
            .map { absolutePath(of: $0, root: root) }
            .removingDuplicates()
    }

    private static func nonEmptyLines(of output: String) -> [String] {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// `ghq list -p` はフルパスを返すが、将来の仕様変更や設定の違いで相対パスが来ても候補にできるよう root と結合する。
    private static func absolutePath(of path: String, root: String) -> String {
        if path.hasPrefix(pathSeparator) {
            return path
        }
        let base = root.hasSuffix(pathSeparator) ? String(root.dropLast()) : root
        return base + pathSeparator + path
    }
}
