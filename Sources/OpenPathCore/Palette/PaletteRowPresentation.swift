/// 候補行に表示する文字列とハイライト（UX-001 §3）。
///
/// 表示名の列と場所の列に分けて出す。通常の場所は親ディレクトリ、別名付きでは実パス全体にし、フルパスが読めるようにする
/// （UX-001 §3 の例 `fern  ~/repos/…/TamaT-LLC`）。
public struct PaletteRowPresentation: Equatable, Sendable {
    /// 表示名。パスの末尾要素でのマッチもここにハイライトする
    public let name: HighlightedText
    /// 場所の表示候補。別名付きでは実パス末尾も含める。ホームは "~" で表し、先頭ほど省略が少ない
    public let locationVariants: [HighlightedText]
    /// フォルダと書類のアイコンを選ぶための種別
    public let isDirectory: Bool

    public init(row: PaletteRow, homeDirectory: String) {
        isDirectory = row.isDirectory
        let path = HighlightedText(row.path, highlightedOffsets: row.pathHighlights)
        let (parent, lastComponent) = PathDisplay.splitParent(path)

        // パス側でマッチした場合、末尾要素の分は場所の列に出ないため表示名の列に移す
        let transferredOffsets = lastComponent.text == row.name ? lastComponent.highlightedOffsets : []
        name = HighlightedText(row.name, highlightedOffsets: row.nameHighlights + transferredOffsets)

        let locationPath = lastComponent.text == row.name ? parent : path
        let location = PathDisplay.abbreviatingHome(locationPath, homeDirectory: homeDirectory)
        locationVariants = PathDisplay.middleTruncations(location)
    }
}
