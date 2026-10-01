/// `InjectionKeyRoute.targetProcess` でキーを送るプロセスを決める。
public enum InjectionKeyDestination {
    /// フォーカス中の要素を持つプロセスを優先し、分からなければ注入先のアプリへ送る。
    /// - Parameters:
    ///   - targetProcessID: 注入の最初に記録した注入先のアプリ。
    ///   - focusedElementProcessID: 注入先のアプリのフォーカス中の要素（AXFocusedUIElement）を持つプロセス。読めなければ nil。
    ///   - ownProcessID: openpath 自身。自分へは送らない。
    public static func processID(targetProcessID: Int32, focusedElementProcessID: Int32?, ownProcessID: Int32) -> Int32 {
        guard let focusedElementProcessID, focusedElementProcessID > 0, focusedElementProcessID != ownProcessID else {
            return targetProcessID
        }
        return focusedElementProcessID
    }
}

/// 注入先でキー入力を受け取る要素（フォーカス中の要素）の種類。⌘⇧G の代替（/）を送ってよいかの判断に使う。
public enum InjectionFocusedElement: String, Equatable, Sendable {
    /// ファイル一覧（カラム表示の列・リスト表示・アイコン表示）。/ を打つと移動先シートが開く
    case fileList
    /// 入力欄（検索欄を含む）。/ を打つと文字として入ってしまう
    case textInput
    /// それ以外（ボタン・サイドバーの外の要素など）
    case other
    /// 読めない
    case unavailable

    /// ファイル一覧のロール。カラム表示ではフォーカスは列の AXList に来る（macOS 27 の自プロセスのパネルで確認）。
    /// リスト表示は AXOutline、アイコン表示は AXList（サブロール AXCollectionList）。
    static let fileListRoles: Set<String> = ["AXList", "AXOutline", "AXTable", "AXBrowser"]
    /// 文字が入る要素のロール。検索欄は AXTextField（サブロール AXSearchField）。
    static let textInputRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]

    /// AX のロール（kAXListRole 等と同じ文字列）から分類する。サブロール（検索欄の AXSearchField 等）は分類を変えないため読まない。
    /// / を送ってよいのは、ファイル一覧と言い切れるときだけにする（サイドバーも AXOutline だが、/ を打っても文字は入らない）。
    public static func classify(role: String?) -> InjectionFocusedElement {
        guard let role else { return .unavailable }
        if fileListRoles.contains(role) {
            return .fileList
        }
        if textInputRoles.contains(role) {
            return .textInput
        }
        return .other
    }
}

/// 注入先のアプリのフォーカス中の要素を読む（AX の抽象）。
@MainActor
public protocol InjectionFocusReading {
    /// 注入先のアプリのフォーカス中の要素の種類。
    /// - Parameter cutoff: 打ち切り条件。AX 操作の直前に確かめること。
    /// - Throws: 読めなければ投げてよい（呼び出し側は `.unavailable` として扱う）。打ち切ったら `ScanCutoff.Reached`。
    func focusedElement(cutoff: ScanCutoff) async throws -> InjectionFocusedElement
}

/// ⌘⇧G を注入先のプロセスへ送っても移動先シートが出なかったときの、もう一度の試み（DSN-001 §3.1）。
///
/// 注入先のプロセスへ送ったキーが届かない（パネルを別プロセスが描いていて届かない等）か、アプリが ⌘⇧G を受け取らなかったとみて、
/// 物理キーボードと同じ経路（`InjectionKeyRoute.systemWide`）で送り直す。
/// - ファイル一覧にフォーカスがあれば / を送る。/ は他アプリのグローバルホットキーにならないため横取りされない。
/// - それ以外（入力欄にフォーカスがある・読めない）は ⌘⇧G を送る。他アプリのグローバルホットキーに横取りされることがある（従来の送り方）。
public struct GoToSheetFallback {
    /// フォーカス中の要素を読む上限。
    public static let focusReadLimit: Duration = .milliseconds(100)

    /// フォーカス中の要素の読み取り。nil なら / を使わず、⌘⇧G だけを送り直す。
    public let focusReader: (any InjectionFocusReading)?

    public init(focusReader: (any InjectionFocusReading)?) {
        self.focusReader = focusReader
    }
}
