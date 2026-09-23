import Foundation
import Observation

/// パレットのビューの状態（UX-001 §3, §5）。
///
/// 検索語はビューの検索フィールドと双方向に結び、候補の差し替えやフッターの状態は
/// 配線側（AppCoordinator の PaletteDisplaying 実装、キー処理）から操作する。
/// ビューと同じく UI スレッドで扱うため MainActor に隔離する。
@MainActor
@Observable
public final class PaletteViewModel {
    /// 検索フィールドの入力。変更を受けて候補を引き直すのは配線側の責務
    public var query = ""
    public private(set) var rows: [PaletteRow] = []
    /// 選択中の候補の添字。候補が 0 件のときだけ nil
    public private(set) var selectedIndex: Int?
    /// 注入中は選択を変えない（DSN-001 §5）。キー入力の破棄はキー処理側で行う
    public private(set) var isLocked = false
    /// 候補ソース（roots / ghq）を構築中か。パレットの表示をまたいで保つ
    public private(set) var isBuildingCandidates = false
    public private(set) var status: PaletteStatus?
    /// 場所の列でホームディレクトリを "~" と表すための基準
    public let homeDirectory: String

    public init(homeDirectory: String = NSHomeDirectory()) {
        self.homeDirectory = homeDirectory
    }

    public var selectedRow: PaletteRow? {
        selectedIndex.map { rows[$0] }
    }

    /// 候補が 0 件のときにリストへ出す案内。候補があれば nil
    public var emptyMessage: String? {
        rows.isEmpty ? PaletteText.noMatches : nil
    }

    /// フッターの表示。エラー・状態表示 > 構築中 > キーヒントの順に優先する。
    public var footer: PaletteFooterContent {
        switch status {
        case .error(let message):
            return .error(message)
        case .info(let message):
            return .status(message)
        case nil:
            return isBuildingCandidates ? .status(PaletteText.buildingCandidates) : .keyHints
        }
    }

    // MARK: - 候補と選択

    /// 候補を差し替える。
    /// - Parameter keepingSelection: true なら選択中の候補（パスで照合）が残っていればその選択を保つ。
    ///   検索語が変わらないまま候補ソースの再構築で候補が増減したときに、選択が先頭へ飛ばないようにする。
    ///   false（既定）または候補が消えた場合は先頭を選択する。
    public func replaceRows(_ newRows: [PaletteRow], keepingSelection: Bool = false) {
        let previousID = keepingSelection ? selectedRow?.id : nil
        rows = newRows
        if let previousID, let index = newRows.firstIndex(where: { $0.id == previousID }) {
            selectedIndex = index
        } else {
            selectedIndex = newRows.isEmpty ? nil : 0
        }
    }

    /// 選択を `offset` 行動かす（正で下、負で上）。先頭・末尾で止め、循環はしない。
    public func moveSelection(by offset: Int) {
        guard !isLocked, let selectedIndex else { return }
        self.selectedIndex = min(max(selectedIndex + offset, 0), rows.count - 1)
    }

    /// 添字で候補を選択する（行のクリック等）。範囲外は無視する。
    public func select(at index: Int) {
        guard !isLocked, rows.indices.contains(index) else { return }
        selectedIndex = index
    }

    // MARK: - 状態表示（PaletteDisplaying の setLocked / showStatus / showError に対応）

    public func setLocked(_ isLocked: Bool) {
        self.isLocked = isLocked
    }

    public func setBuildingCandidates(_ isBuilding: Bool) {
        isBuildingCandidates = isBuilding
    }

    public func showStatus(_ message: String) {
        status = .info(message)
    }

    public func showError(_ message: String) {
        status = .error(message)
    }

    public func clearStatus() {
        status = nil
    }

    /// 新しいパネルに対してパレットを出し直すときに、前回の検索・選択・状態表示を消す。
    /// 候補ソースの構築状況はパネルに依らないため保つ。
    public func reset() {
        query = ""
        rows = []
        selectedIndex = nil
        isLocked = false
        status = nil
    }
}
