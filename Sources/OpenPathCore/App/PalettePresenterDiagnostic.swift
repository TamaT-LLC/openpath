/// パレットの表示・閉じる・候補の引き直し（`PalettePresenter`）の診断。debug ログに出す。
///
/// 実機 QA で、パレットの初出に「一致する候補がありません」を挟まないか（FLOW-01）、パレットを閉じた時刻（S-08）、
/// 履歴のクリアで表示中の候補を引き直したか（MENU-04・MENU-05）を、ログの行で判定するためのもの。
/// 行数・空状態の案内の有無・待ち時間・パネル ID だけを持ち、候補のパス・名前と検索語は持たない。
///
/// 文言は `palette shown`（検知レイテンシの計測スクリプトが部分一致で読む）を含まない別の行にする。
public enum PalettePresenterDiagnostic: Equatable, Sendable {
    /// ウィンドウを出した（`palette shown` の直後に報告する）
    case revealed(PaletteRevealRecord)
    /// 表示中の（または最初の候補を待っていた）パレットを閉じた
    case hidden(panelID: PanelContext.ID, wasVisible: Bool)
    /// 候補の差し替え（履歴のクリアで履歴の候補を取り除いた後）を受けた。表示していなければ panelID は nil
    case candidatesChanged(panelID: PanelContext.ID?, isBuildingCandidates: Bool)
    /// 検索語の変更以外の契機で引き直した候補を、表示中のパレットに反映した
    case rowsRefreshed(PaletteRowsRefreshRecord)

    /// debug ログの文言。例:
    /// - `palette reveal (id: open-panel-3, rows: 8, emptyMessage: false, waitedForInitialRows: true, waited: 34ms, waitLimitReached: false)`
    /// - `palette hidden (id: open-panel-3, wasVisible: true)`
    /// - `palette candidates changed (presented: true, id: open-panel-3, building: true)`
    /// - `palette rows refreshed (id: open-panel-3, trigger: candidatesChanged, rows: 7, lastUsedRows: 0, selectionKept: false)`
    public var logMessage: String {
        switch self {
        case .revealed(let record):
            return "palette reveal (\(record.logFields.joined(separator: ", ")))"
        case .hidden(let panelID, let wasVisible):
            return "palette hidden (id: \(panelID.rawValue), wasVisible: \(wasVisible))"
        case .candidatesChanged(let panelID, let isBuildingCandidates):
            let presented = panelID.map { "presented: true, id: \($0.rawValue)" } ?? "presented: false"
            return "palette candidates changed (\(presented), building: \(isBuildingCandidates))"
        case .rowsRefreshed(let record):
            return "palette rows refreshed (id: \(record.panelID.rawValue), trigger: \(record.trigger.rawValue), "
                + "rows: \(record.rowCount), lastUsedRows: \(record.lastUsedRowCount), selectionKept: \(record.isSelectionKept))"
        }
    }

    /// 既定の報告先。debug ログに出す（リリースビルドの既定の info では出さない）。
    public static func log(_ diagnostic: PalettePresenterDiagnostic) {
        Log.debug(diagnostic.logMessage)
    }
}

/// ウィンドウを出した時点のパレット。
public struct PaletteRevealRecord: Equatable, Sendable {
    /// 最初の候補を待ったか
    public enum InitialRows: Equatable, Sendable {
        /// 候補を受け取り済みで、待たずに出した（同じパネルの再表示）
        case alreadyReceived
        /// 最初の候補が届いてから出した。after は `show` から出すまでの時間
        case received(after: Duration)
        /// 待ちの上限（`PalettePresenter.initialRowsWaitLimit`）に達したため、候補を待たずに出した
        case waitLimitReached(after: Duration)
    }

    public let panelID: PanelContext.ID
    /// 出した時点の行数
    public let rowCount: Int
    /// 出した時点で、リストに「一致する候補がありません」を出しているか（`PaletteViewModel.emptyMessage`）
    public let showsEmptyMessage: Bool
    public let initialRows: InitialRows

    public init(panelID: PanelContext.ID, rowCount: Int, showsEmptyMessage: Bool, initialRows: InitialRows) {
        self.panelID = panelID
        self.rowCount = rowCount
        self.showsEmptyMessage = showsEmptyMessage
        self.initialRows = initialRows
    }

    fileprivate var logFields: [String] {
        let fields = ["id: \(panelID.rawValue)", "rows: \(rowCount)", "emptyMessage: \(showsEmptyMessage)"]
        switch initialRows {
        case .alreadyReceived:
            return fields + ["waitedForInitialRows: false"]
        case .received(let waited):
            return fields + ["waitedForInitialRows: true", "waited: \(InjectionLogFormat.milliseconds(waited))", "waitLimitReached: false"]
        case .waitLimitReached(let waited):
            return fields + ["waitedForInitialRows: true", "waited: \(InjectionLogFormat.milliseconds(waited))", "waitLimitReached: true"]
        }
    }
}

/// 検索語の変更以外の契機で引き直した候補の反映。
public struct PaletteRowsRefreshRecord: Equatable, Sendable {
    /// 引き直した契機
    public enum Trigger: String, Equatable, Sendable {
        /// 全件の再構築を終えた（`candidateRebuildingDidChange`）
        case rebuildFinished
        /// 候補が差し替わった（履歴のクリア。`candidatesDidChange`）
        case candidatesChanged
        /// 選択モードの推定し直しで、フォルダのみかどうかが変わった（`update(context:)`）
        case panelContextChanged
    }

    public let panelID: PanelContext.ID
    public let trigger: Trigger
    /// 反映した行数
    public let rowCount: Int
    /// 反映した行のうち、最終使用日時を持つ（履歴にある）行の数
    public let lastUsedRowCount: Int
    /// 引き直す前に選んでいた候補を選んだままか。消えていた（先頭を選び直した）・選んでいなかった場合は false
    public let isSelectionKept: Bool

    public init(panelID: PanelContext.ID, trigger: Trigger, rowCount: Int, lastUsedRowCount: Int, isSelectionKept: Bool) {
        self.panelID = panelID
        self.trigger = trigger
        self.rowCount = rowCount
        self.lastUsedRowCount = lastUsedRowCount
        self.isSelectionKept = isSelectionKept
    }
}
