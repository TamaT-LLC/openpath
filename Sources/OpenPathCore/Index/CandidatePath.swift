/// 候補のパスの正規化と表示名の取り出し。
///
/// 同じ場所が別の表記（末尾の `/`、`//`、`.`、`..`）で複数のソースや履歴に現れても 1 件に統合できるよう、
/// ファイルシステムを引かずに字句的に正規化したパスを統合キーにする（RootPathResolver と同じ規則）。
/// シンボリックリンクの解決と大文字小文字の同一視は行わない（別の場所を 1 件にしてしまう恐れがあるため）。
/// NFC / NFD の違いは String の比較（正準等価）で同じキーになるため、ここでは揃えない。
enum CandidatePath {
    private static let separator = "/"
    private static let separatorByte = UInt8(ascii: "/")
    private static let dotByte = UInt8(ascii: ".")
    private static let parentDirectoryByteCount = 2

    /// 正規化した絶対パス。絶対パスでなければ移動先にできないため nil。
    /// 既に正規化済みのパス（大半の候補）は、文字列を作り直さずにそのまま返す。
    static func normalized(_ path: String) -> String? {
        guard path.hasPrefix(separator) else { return nil }
        return isNormalized(path) ? path : RootPathResolver.normalize(absolutePath: path)
    }

    /// パスの末尾要素。ルートは "/" のまま返す。
    static func name(of normalizedPath: String) -> String {
        guard let lastSeparator = normalizedPath.lastIndex(of: Character(separator)),
              normalizedPath.index(after: lastSeparator) < normalizedPath.endIndex
        else {
            return normalizedPath
        }
        return String(normalizedPath[normalizedPath.index(after: lastSeparator)...])
    }

    /// 空要素（`//`・末尾の `/`）と `.`・`..` の要素を含まないか。ルート "/" は正規化済みとする。
    /// 履歴の表引きをクエリのたびに作るため、文字列を分割せずにバイト列を 1 回なめて判定する。
    private static func isNormalized(_ path: String) -> Bool {
        // 先頭の "/" の後ろから要素を数える
        let components = path.utf8.dropFirst()
        guard !components.isEmpty else { return true }
        var length = 0
        var isAllDots = true
        for byte in components {
            guard byte == separatorByte else {
                length += 1
                isAllDots = isAllDots && byte == dotByte
                continue
            }
            guard isKeptComponent(length: length, isAllDots: isAllDots) else { return false }
            length = 0
            isAllDots = true
        }
        return isKeptComponent(length: length, isAllDots: isAllDots)
    }

    /// 正規化で取り除かれない要素（空でも `.` / `..` でもない）か
    private static func isKeptComponent(length: Int, isAllDots: Bool) -> Bool {
        length > 0 && !(isAllDots && length <= parentDirectoryByteCount)
    }
}
