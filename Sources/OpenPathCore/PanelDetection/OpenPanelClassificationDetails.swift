/// パネルの候補の子孫の要約。debug ログで、どの条件で弾いたのかを実機のログから見分けるために集める（Issue #83）。
///
/// `OpenPanelClassifier.classification(of:reader:search:collectingDetails:)` が、判定と同じ幅優先探索で見た要素から作る。
/// ボタンの表題とロール名は持つが、入力欄の文字列やウィンドウタイトルは持たない。入力欄は、説明・タイトルの有無と、
/// 保存パネルの語（`OpenPanelCriteria.saveFieldKeywords`）のどれにどの属性が一致したかだけを持つ。
public struct OpenPanelClassificationDetails: Equatable, Sendable {
    /// 子孫の AXButton。
    public struct Button: Equatable, Sendable {
        /// `AXTitle`。
        public let title: String?
        /// `AXEnabled`。読めなければ nil。
        public let isEnabled: Bool?
        /// `AXDescription` を持つか。
        public let hasDescription: Bool
        /// `AXDescription` が確定ボタンのタイトル（条件 2）と一致するなら、その説明（前後の空白を除く）。一致しなければ nil。
        /// 表題をタイトルでなく説明に持つボタンを見分ける。確定ボタンのタイトル以外の説明の文字列は持たない。
        public let descriptionConfirmTitle: String?

        /// タイトルが確定ボタンのタイトル（条件 2）か。
        public var isConfirm: Bool {
            title.map(OpenPanelCriteria.isConfirmButtonTitle) ?? false
        }

        public init(title: String?, isEnabled: Bool?, hasDescription: Bool, descriptionConfirmTitle: String?) {
            self.title = title
            self.isEnabled = isEnabled
            self.hasDescription = hasDescription
            self.descriptionConfirmTitle = descriptionConfirmTitle
        }
    }

    /// 子孫の一覧らしい要素（ファイル一覧のロール、AXList、AXWebArea）。判定では中へ降りない。
    public struct ListElement: Equatable, Sendable {
        public let role: String
        public let subrole: String?
        /// ファイル一覧（条件 3）とみなしたか。
        public let isFileList: Bool

        public init(role: String, subrole: String?, isFileList: Bool) {
            self.role = role
            self.subrole = subrole
            self.isFileList = isFileList
        }
    }

    /// 入力欄が保存パネルの語を含んでいたこと。
    public struct SaveKeywordMatch: Equatable, Sendable {
        /// 語が見つかった属性。
        public enum Source: String, Sendable {
            case description = "desc"
            case title
        }

        public let source: Source
        /// `OpenPanelCriteria.saveFieldKeywords` のいずれか（入力欄の文字列そのものではない）。
        public let keyword: String

        public init(source: Source, keyword: String) {
            self.source = source
            self.keyword = keyword
        }
    }

    /// 子孫の AXTextField。
    public struct TextField: Equatable, Sendable {
        /// `AXSubrole`（検索欄なら AXSearchField）。
        public let subrole: String?
        public let hasDescription: Bool
        public let hasTitle: Bool
        /// 保存パネルの語に一致したか（条件 4）。一致しなければ nil。
        public let saveKeywordMatch: SaveKeywordMatch?

        public init(subrole: String?, hasDescription: Bool, hasTitle: Bool, saveKeywordMatch: SaveKeywordMatch?) {
            self.subrole = subrole
            self.hasDescription = hasDescription
            self.hasTitle = hasTitle
            self.saveKeywordMatch = saveKeywordMatch
        }
    }

    /// 幅優先の順のボタン。
    public internal(set) var buttons: [Button] = []
    /// 幅優先の順の一覧らしい要素。
    public internal(set) var lists: [ListElement] = []
    /// 幅優先の順の入力欄。
    public internal(set) var textFields: [TextField] = []
    /// 訪問した要素のロールごとの数。ロールを読めなかった要素は "nil"。
    public internal(set) var roleCounts: [String: Int] = [:]
    /// 訪問した子孫の数。
    public internal(set) var visitedCount = 0
    /// 訪問した子孫の最も深い階層（候補の直下が 1）。
    public internal(set) var deepestLevel = 0
    /// 深さの上限の要素のうち、子を持つため中を調べられなかったものの数。
    public internal(set) var unexploredAtDepthLimit = 0
    /// 探索の上限（`BoundedBreadthFirstSearch`）。
    public let maxVisitedNodes: Int
    public let maxDepth: Int
    /// 要約のためだけに行った AX の読み取りの回数。判定のコストのログ（`axCalls`）から除くために数える。
    public internal(set) var diagnosticReadCount = 0

    /// 探索の上限で打ち切ったか（訪問数の上限に達した、または深さの上限の先に子孫が残っていた）。
    public var isTruncated: Bool {
        visitedCount >= maxVisitedNodes || unexploredAtDepthLimit > 0
    }

    init(search: BoundedBreadthFirstSearch) {
        maxVisitedNodes = search.maxVisitedNodes
        maxDepth = search.maxDepth
    }
}
