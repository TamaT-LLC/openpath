/// メニューバーのメニューから実行できる操作（UX-001 §6, FR-CONFIG-02/03）。
/// `allCases` のうちメニューの項目に並ぶもの（`appearsAsMenuItem`）の順が、メニューでの並び順。
public enum StatusMenuCommand: Sendable, Hashable, CaseIterable {
    /// 有効（チェック切替）
    case toggleEnabled
    /// 候補を再構築
    case rebuildCandidates
    /// 設定ファイルを開く…
    case openConfigFile
    /// 履歴をクリア…（確認ダイアログを挟む）
    case clearHistory
    /// ログイン時に起動（チェック切替）
    case toggleLaunchAtLogin
    /// アクセシビリティ設定を開く…（未付与時のみ）
    case openAccessibilitySettings
    /// 終了
    case quit
    /// クリップボードの復元失敗の通知を消す。通知を選んだときだけ行い、メニューの項目には並ばない
    case dismissClipboardNotice

    /// メニューの項目として並ぶか。通知から選ぶだけの操作は false
    public var appearsAsMenuItem: Bool {
        self != .dismissClipboardNotice
    }

    public var title: String {
        switch self {
        case .toggleEnabled: StatusMenuText.toggleEnabled
        case .rebuildCandidates: StatusMenuText.rebuildCandidates
        case .openConfigFile: StatusMenuText.openConfigFile
        case .clearHistory: StatusMenuText.clearHistory
        case .toggleLaunchAtLogin: StatusMenuText.toggleLaunchAtLogin
        case .openAccessibilitySettings: StatusMenuText.openAccessibilitySettings
        case .quit: StatusMenuText.quit
        case .dismissClipboardNotice: StatusMenuText.dismissNotice
        }
    }

    /// ⌘ と組み合わせるキー。無ければ空文字（NSMenuItem.keyEquivalent の表現に合わせる）
    public var keyEquivalent: String {
        switch self {
        case .openConfigFile: StatusMenuText.settingsKeyEquivalent
        case .quit: StatusMenuText.quitKeyEquivalent
        case .toggleEnabled, .rebuildCandidates, .clearHistory, .toggleLaunchAtLogin, .openAccessibilitySettings,
             .dismissClipboardNotice: ""
        }
    }
}
