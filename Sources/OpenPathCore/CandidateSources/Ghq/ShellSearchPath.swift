/// PATH 形式（`:` 区切り）の検索パスの操作。
enum ShellSearchPath {
    static let entrySeparator: Character = ":"
    static let pathSeparator = "/"

    /// 絶対パスのエントリだけを、重複は最初の出現を残して返す。
    /// 空のエントリや相対パスはカレントディレクトリとして解釈され、意図しない実行ファイルを拾い得るため除く。
    static func absoluteEntries(of searchPath: String) -> [String] {
        searchPath.split(separator: entrySeparator)
            .map(String.init)
            .filter { $0.hasPrefix(pathSeparator) }
            .removingDuplicates()
    }

    static func join(_ entries: [String]) -> String {
        entries.joined(separator: String(entrySeparator))
    }
}

extension Array where Element: Hashable {
    /// 重複を除いた配列。順序は最初に出現した位置を保つ。
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
