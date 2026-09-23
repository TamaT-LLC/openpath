/// 候補行に表示する文字列とハイライト（UX-001 §3）。
///
/// 表示名の列と場所の列に分けて出す。場所は候補の親ディレクトリで、表示名と並べてフルパスが読めるようにする
/// （UX-001 §3 の例 `fern  ~/repos/…/TamaT-LLC`）。
public struct PaletteRowPresentation: Equatable, Sendable {
    /// 表示名。パスの末尾要素でのマッチもここにハイライトする
    public let name: HighlightedText
    /// 場所（親ディレクトリ）の表示候補。ホームは "~" で表し、先頭ほど省略が少ない。常に 1 件以上ある
    public let locationVariants: [HighlightedText]

    public init(row: PaletteRow, homeDirectory: String) {
        let path = HighlightedText(row.path, highlightedOffsets: row.pathHighlights)
        let (parent, lastComponent) = PathDisplay.splitParent(path)

        // パス側でマッチした場合、末尾要素の分は場所の列に出ないため表示名の列に移す
        let transferredOffsets = lastComponent.text == row.name ? lastComponent.highlightedOffsets : []
        name = HighlightedText(row.name, highlightedOffsets: row.nameHighlights + transferredOffsets)

        let location = PathDisplay.abbreviatingHome(parent, homeDirectory: homeDirectory)
        locationVariants = PathDisplay.middleTruncations(location)
    }
}
