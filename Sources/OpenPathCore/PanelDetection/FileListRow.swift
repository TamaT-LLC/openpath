/// ファイル一覧の 1 行から読み取った値（DSN-001 §2.3）。選択モードの推定に使う。
///
/// NSOpenPanel のファイル一覧（FinderKit）では、選べない行の見え方が表示形式によって異なる（macOS 26 で確認）:
/// - リスト表示（AXOutline）・カラム表示（AXBrowser）: AXEnabled は true のままで、名前の文字色だけが淡くなる
/// - アイコン表示（AXList / AXCollectionList）: 項目の AXImage の AXEnabled が false になる。文字列を持たないため文字色は読めない
///
/// そのため、AXEnabled が false か、名前の文字色が淡い行を「選べない行」とみなす。
/// アイコン表示の行は `isEnabledAuthoritative` を true にし、AXEnabled が true なら「選べる行」とみなす。
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
    /// AXEnabled が選べるかどうかをそのまま表すか。アイコン表示の項目は true（選べるファイルは true、選べないファイルは false）。
    /// リスト表示・カラム表示の行は、選べない行も AXEnabled が true のままなので false。
    public let isEnabledAuthoritative: Bool

    public init(isDirectory: Bool?, isEnabled: Bool? = nil, textOpacity: Double? = nil, isEnabledAuthoritative: Bool = false) {
        self.isDirectory = isDirectory
        self.isEnabled = isEnabled
        self.textOpacity = textOpacity
        self.isEnabledAuthoritative = isEnabledAuthoritative
    }

    /// 選べる行か。判断できなければ nil。
    ///
    /// `isEnabledAuthoritative` でなければ、AXEnabled が true でも文字色を読めなければ判断しない。
    /// リスト表示・カラム表示では、選べない行も AXEnabled が true のため。
    public var isSelectable: Bool? {
        if isEnabled == false {
            return false
        }
        if isEnabledAuthoritative, isEnabled == true {
            return true
        }
        guard let textOpacity else { return nil }
        return textOpacity >= Self.dimmedTextOpacityThreshold
    }
}
