/// ファイル一覧の 1 行から読み取った値（DSN-001 §2.3）。選択モードの推定に使う。
///
/// NSOpenPanel のファイル一覧（FinderKit）では、選べない行の見え方が表示形式によって異なる（macOS 26 で確認）:
/// - リスト表示（AXOutline）・カラム表示（AXBrowser）: AXEnabled は true のままで、名前の文字色だけが淡くなる
/// - アイコン表示: 項目の AXEnabled が false になる
///
/// そのため、AXEnabled が false か、名前の文字色が淡い行を「選べない行」とみなす。
public struct FileListRow: Equatable, Sendable {
    /// 名前の文字色の不透明度がこれ未満なら、淡色（選べない行）とみなす。
    /// macOS 26 の実測では、選べる行（選択中の行を含む）は 0.85、選べない行はダークで 0.25、ライトで 0.26。
    public static let dimmedTextOpacityThreshold = 0.5

    /// ディレクトリか（名前の要素の AXURL の末尾が "/" か）。URL を読めない行（見出しの行など）は nil。
    public let isDirectory: Bool?
    /// 名前の要素の AXEnabled。読んでいなければ nil。
    public let isEnabled: Bool?
    /// 名前の文字色の不透明度（0〜1）。読めなければ nil。
    public let textOpacity: Double?

    public init(isDirectory: Bool?, isEnabled: Bool? = nil, textOpacity: Double? = nil) {
        self.isDirectory = isDirectory
        self.isEnabled = isEnabled
        self.textOpacity = textOpacity
    }

    /// 選べる行か。判断できなければ nil。
    ///
    /// AXEnabled が true でも文字色を読めなければ判断しない。リスト表示・カラム表示では、選べない行も AXEnabled が true のため。
    public var isSelectable: Bool? {
        if isEnabled == false {
            return false
        }
        guard let textOpacity else { return nil }
        return textOpacity >= Self.dimmedTextOpacityThreshold
    }
}
