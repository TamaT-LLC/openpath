import Foundation

/// NSOpenPanel の判定条件（DSN-001 §2.2、ARCH-001 §6）。
///
/// ロール名などは AX の定数（`kAXSheetRole` 等）と同じ文字列。Core に ApplicationServices を持ち込まないため文字列で持つ。
public enum OpenPanelCriteria {
    public static let dialogSubrole = "AXDialog"
    /// シートはロールが `AXSheet` になる。DSN-001 のコードに合わせ、サブロールが `AXSheet` の要素も対象にする。
    public static let sheetRole = "AXSheet"
    public static let buttonRole = "AXButton"
    public static let textFieldRole = "AXTextField"
    /// ファイル一覧のロール（条件 3）。
    public static let fileListRoles: Set<String> = ["AXBrowser", "AXOutline", "AXTable"]
    /// 確定ボタンのタイトル（条件 2）。前後の空白を除いて完全一致で比べる。
    /// Safari の `input[type=file]` は確定ボタンが「アップロード」になるため、DSN-001 の一覧に加えている。
    public static let confirmButtonTitles: Set<String> = [
        "開く", "Open", "選択", "Choose", "追加", "Add", "アップロード", "Upload",
    ]
    /// 保存パネルのファイル名欄を示す語（条件 4）。入力欄の AXDescription か AXTitle に含まれていれば保存パネルとみなす。
    public static let saveFieldKeywords = ["Save", "保存", "名前"]
    /// 候補の判定で中へ降りない要素。
    /// - ファイル一覧など: 行やセルが大量にあり AX の往復がかさむうえ、行のファイル名（「保存」を含む等）を
    ///   保存パネルの入力欄と誤認しないため。ファイル一覧は存在だけ分かればよい
    /// - シート: 候補に付いた別のウィンドウ（⌘⇧G の移動先シートや、ダイアログの上に出たパネル）。
    ///   中身を候補の判定に含めると、シートが閉じても候補がパネルのままキャッシュに残るため
    static let prunedRoles: Set<String> = fileListRoles.union(["AXList", "AXWebArea", sheetRole])

    /// シートの入れ子を探す深さ。ウィンドウの子のシートを 1 段目と数える。
    /// 開くパネルと判定しなかったシート（リモートビューの外側のシートなど）の子のシートまで探す。
    public static let maxSheetNestingDepth = 2
    /// `PanelContext.ID` の接頭辞。後ろに連番を付ける。
    static let panelIDPrefix = "open-panel-"

    /// パネルの候補（条件 1）か。ダイアログのウィンドウとシートが対象。
    public static func isPanelCandidate(role: String?, subrole: String?) -> Bool {
        role == sheetRole || subrole == dialogSubrole || subrole == sheetRole
    }

    /// 確定ボタンのタイトルか（条件 2）。
    public static func isConfirmButtonTitle(_ title: String) -> Bool {
        confirmButtonTitles.contains(title.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 保存パネルのファイル名欄の説明・タイトルか（条件 4）。
    public static func isSaveFieldLabel(_ label: String) -> Bool {
        saveFieldKeywords.contains { label.contains($0) }
    }
}
