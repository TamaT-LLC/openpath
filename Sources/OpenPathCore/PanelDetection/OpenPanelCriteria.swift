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
    /// ファイル一覧のロール（条件 3）。カラム表示（AXBrowser）とリスト表示（AXOutline / AXTable）。
    public static let fileListRoles: Set<String> = ["AXBrowser", "AXOutline", "AXTable"]
    /// アイコン表示のファイル一覧（条件 3）のロールとサブロール。FinderKit のアイコン表示は NSCollectionView で、
    /// ロールが AXList、サブロールが AXCollectionList になる。
    /// AXList は設定のシートの一覧などにも使われるため、サブロールが AXCollectionList のものに限る。
    public static let collectionListRole = "AXList"
    public static let collectionListSubrole = "AXCollectionList"
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
    static let prunedRoles: Set<String> = fileListRoles.union([collectionListRole, "AXWebArea", sheetRole])

    /// シートの入れ子を探す深さ。ウィンドウの子のシートを 1 段目と数える。
    /// 開くパネルと判定しなかったシート（リモートビューの外側のシートなど）の子のシートまで探す。
    public static let maxSheetNestingDepth = 2
    /// `PanelContext.ID` の接頭辞。後ろに連番を付ける。
    static let panelIDPrefix = "open-panel-"

    /// NSOpenPanel のウィンドウの `AXIdentifier`（NSSavePanel は `save-panel`）。
    /// 非モーダルのパネル（NSDocumentController の「ファイル > 開く…」、`begin(completionHandler:)`）は、ウィンドウの
    /// サブロールが AXDialog ではなく AXStandardWindow になるため、この識別子で候補にする（Issue #83。macOS 27 の
    /// 自プロセスのパネルで、非モーダル・モーダルとも `open-panel` であることを確認）。ローカライズされない。
    public static let openPanelIdentifier = "open-panel"

    /// パネルの候補（条件 1）か。ダイアログのウィンドウ、シート、AXIdentifier が `open-panel` のウィンドウが対象。
    public static func isPanelCandidate(role: String?, subrole: String?, identifier: String? = nil) -> Bool {
        candidateReason(role: role, subrole: subrole, identifier: identifier) != nil
    }

    /// パネルの候補（条件 1）にする理由。候補でなければ nil。
    public static func candidateReason(role: String?, subrole: String?, identifier: String?) -> PanelCandidateReason? {
        if role == sheetRole || subrole == sheetRole {
            return .sheet
        }
        if subrole == dialogSubrole {
            return .dialog
        }
        if identifier == openPanelIdentifier {
            return .openPanelIdentifier
        }
        return nil
    }

    /// 保存パネルのファイル名欄を示す語のうち、label に含まれる最初のもの（条件 4）。含まれなければ nil。
    public static func saveFieldKeyword(in label: String) -> String? {
        saveFieldKeywords.first { label.contains($0) }
    }

    /// ファイル一覧か（条件 3）。サブロールは、ロールが `collectionListRole`（AXList）のときだけ見る。
    public static func isFileList(role: String, subrole: String?) -> Bool {
        fileListRoles.contains(role) || (role == collectionListRole && subrole == collectionListSubrole)
    }

    /// 確定ボタンのタイトルか（条件 2）。
    public static func isConfirmButtonTitle(_ title: String) -> Bool {
        confirmButtonTitles.contains(title.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 保存パネルのファイル名欄の説明・タイトルか（条件 4）。
    public static func isSaveFieldLabel(_ label: String) -> Bool {
        saveFieldKeyword(in: label) != nil
    }
}
