import AppKit

import OpenPathCore

/// メニューで選ばれた操作のうち、他のモジュールに属するものの実行先（UX-001 §6）。
///
/// StatusItem が AppCoordinator・ConfigStore・HistoryStore・CandidateIndex に直接依存しないよう、
/// 呼び出し側（AppDelegate）が配線する。nil のままの操作はメニューで選べないようにする。
/// StatusItemController の init の既定値として非隔離の文脈でも作れるよう、型は MainActor に隔離せず、各処理だけを隔離する。
public struct StatusMenuActions {
    /// 「有効」を切り替えたとき。引数は切り替え後の値。StatusItem のチェックは先に切り替わっている
    public var setEnabled: (@MainActor (Bool) -> Void)?
    /// 「候補を再構築」
    public var rebuildCandidates: (@MainActor () -> Void)?
    /// 「履歴をクリア…」の確認ダイアログでクリアを選んだとき
    public var clearHistory: (@MainActor () -> Void)?
    /// 「アクセシビリティ設定を開く…」とメニュー先頭の権限の通知
    public var openAccessibilitySettings: @MainActor () -> Void
    /// 「終了」
    public var quit: @MainActor () -> Void

    public init(
        setEnabled: (@MainActor (Bool) -> Void)? = nil,
        rebuildCandidates: (@MainActor () -> Void)? = nil,
        clearHistory: (@MainActor () -> Void)? = nil,
        openAccessibilitySettings: @escaping @MainActor () -> Void = { AccessibilityPermission.openSystemSettings() },
        quit: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) }
    ) {
        self.setEnabled = setEnabled
        self.rebuildCandidates = rebuildCandidates
        self.clearHistory = clearHistory
        self.openAccessibilitySettings = openAccessibilitySettings
        self.quit = quit
    }

    /// 実行先が配線されているか。StatusItem 自身が実行する操作は常に true
    func canPerform(_ command: StatusMenuCommand) -> Bool {
        switch command {
        case .toggleEnabled: setEnabled != nil
        case .rebuildCandidates: rebuildCandidates != nil
        case .clearHistory: clearHistory != nil
        case .openConfigFile, .toggleLaunchAtLogin, .openAccessibilitySettings, .quit: true
        }
    }
}
