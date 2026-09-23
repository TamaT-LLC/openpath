import Foundation

/// Tab で選択候補のパスを検索語に展開するときの検索語（UX-001 §4「サブディレクトリを掘る」）。
///
/// 展開後の検索語はそのままファジーマッチに使われるため、候補の `path` と同じ絶対パスで展開する
/// （"~" に縮めると、絶対パスを持つ候補にマッチしなくなる）。
public enum PaletteQueryExpansion {
    private static let separator: Character = "/"

    /// ディレクトリは末尾に "/" を付ける。シェルの補完と同じく、続けて配下の名前を打てば
    /// そのディレクトリの中だけに候補が絞られ、選んだディレクトリ自身は候補から外れる。
    /// ファイルは掘り下げられないため、パスをそのまま返す。
    public static func query(expanding path: String, isDirectory: Bool) -> String {
        guard isDirectory, path.last != separator else { return path }
        return path + String(separator)
    }

    /// パスが既存のディレクトリを指すか。シンボリックリンクは辿る（ghq のリンク運用を想定）。
    public static func isExistingDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
