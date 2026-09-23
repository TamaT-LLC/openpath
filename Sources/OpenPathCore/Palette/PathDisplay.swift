/// パレットの候補行に出すパスの整形（UX-001 §3）。
///
/// どの操作もハイライト位置を整形後の文字列に合わせて付け替える。
/// 文字列の比較は Character 単位（Unicode の正準等価）で行うため、NFC / NFD の違いは同じ文字として扱う。
public enum PathDisplay {
    /// 中央省略で取り除いたディレクトリの代わりに置く記号
    public static let ellipsis: Character = "…"
    /// ホームディレクトリの代わりに置く記号
    public static let homeSymbol: Character = "~"

    private static let separator: Character = "/"
    /// 中央省略で必ず残す要素数（先頭と末尾の 1 つずつ）
    private static let minimumKeptComponentCount = 2

    /// パスを親ディレクトリと末尾要素に分ける。ハイライトもそれぞれの文字列へ振り分ける。
    ///
    /// 末尾のスラッシュは無視する。ルート直下の要素の親は "/"、スラッシュを含まないパスの親は空文字列。
    public static func splitParent(_ path: HighlightedText) -> (parent: HighlightedText, lastComponent: HighlightedText) {
        let characters = Array(path.text)
        var end = characters.count
        while end > 1, characters[end - 1] == separator {
            end -= 1
        }
        guard let lastSeparator = characters[..<end].lastIndex(of: separator) else {
            return (HighlightedText(""), path.slice(0..<end))
        }
        // ルート直下の要素（"/Users" 等）は親を "/" として残す
        let parentEnd = lastSeparator == 0 ? 1 : lastSeparator
        let lastComponentStart = min(lastSeparator + 1, end)
        return (path.slice(0..<parentEnd), path.slice(lastComponentStart..<end))
    }

    /// ホームディレクトリとその配下のパスの先頭を "~" に置き換える。
    ///
    /// "/Users/examples" のように要素の途中までしか一致しないパスは置き換えない。
    /// ホームディレクトリ部分のハイライトは "~" に集約する。
    public static func abbreviatingHome(_ path: HighlightedText, homeDirectory: String) -> HighlightedText {
        var home = Array(homeDirectory)
        while home.count > 1, home.last == separator {
            home.removeLast()
        }
        // ホームが取れない・ルートの場合に全パスを "~" 扱いしないよう、置き換えない
        guard home.count > 1 else { return path }

        let characters = Array(path.text)
        guard characters.starts(with: home) else { return path }
        let isAtComponentBoundary = characters.count == home.count || characters[home.count] == separator
        guard isAtComponentBoundary else { return path }

        return path.replacingCharacters(in: 0..<home.count, with: homeSymbol)
    }

    /// 中間のディレクトリを "…" にまとめた候補を、省略の少ない順に返す。先頭は元のパス。
    ///
    /// 先頭の要素（"~" やルート）と末尾の要素は必ず残す。残す要素は先頭側を 1 つ多めにする
    /// （UX-001 §3 の例 `~/repos/…/TamaT-LLC` に合わせる）。
    /// ビューは表示幅に収まる最初の候補を使う。どれも収まらない場合は最後の候補を文字単位で省略する。
    /// 省略した部分のハイライトは "…" に集約する。
    public static func middleTruncations(_ path: HighlightedText) -> [HighlightedText] {
        let components = componentRanges(of: Array(path.text))
        let componentCount = components.count
        guard componentCount > minimumKeptComponentCount else { return [path] }

        let truncated = stride(from: componentCount - 1, through: minimumKeptComponentCount, by: -1).map { keptCount in
            let headCount = (keptCount + 1) / 2
            let tailCount = keptCount - headCount
            let elidedRange = components[headCount].lowerBound..<components[componentCount - tailCount - 1].upperBound
            return path.replacingCharacters(in: elidedRange, with: ellipsis)
        }
        return [path] + truncated
    }

    /// "/" で区切った各要素の Character オフセットの範囲。空の要素（先頭のルート等）も含む。
    private static func componentRanges(of characters: [Character]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        for (offset, character) in characters.enumerated() where character == separator {
            ranges.append(start..<offset)
            start = offset + 1
        }
        ranges.append(start..<characters.count)
        return ranges
    }
}
