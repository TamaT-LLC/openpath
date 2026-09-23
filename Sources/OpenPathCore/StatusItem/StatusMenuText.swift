/// メニューバーのメニュー・ツールチップ・ダイアログの文言（UX-001 §5, §6）。
enum StatusMenuText {
    // MARK: - メニュー項目

    static let toggleEnabled = "有効"
    static let rebuildCandidates = "候補を再構築"
    static let openConfigFile = "設定ファイルを開く…"
    static let clearHistory = "履歴をクリア…"
    static let toggleLaunchAtLogin = "ログイン時に起動"
    static let openAccessibilitySettings = "アクセシビリティ設定を開く…"
    static let quit = "終了"

    /// macOS の慣習（⌘, で設定、⌘Q で終了）に合わせる
    static let settingsKeyEquivalent = ","
    static let quitKeyEquivalent = "q"

    // MARK: - 通知

    static let permissionMissingTitle = "アクセシビリティ権限がありません"
    static let permissionMissingDetail = "パネルの検知とパスの入力に使います。システム設定で openpath を許可してください"
    static let configErrorTitle = "設定ファイルにエラーがあります"
    static let clipboardRestoreFailedTitle = "クリップボードを元に戻せませんでした"
    static let clipboardRestoreFailedDetail = "「開く」まで自動で押した後、コピーしていた内容を元に戻せませんでした。必要ならコピーし直してください。選ぶとこの通知を消します"
    static let dismissNotice = "通知を消す"

    // MARK: - ログイン時に起動

    static let loginItemRequiresApproval = "システム設定の「一般 > ログイン項目」で許可すると有効になります"
    static let loginItemUnavailable = "\(AppInfo.name).app として起動したときだけ設定できます"

    // MARK: - アイコン

    static let disabledSuffix = "無効"
    static let attentionSuffix = "要対応"
    static let labelSeparator = "・"
    static let noticeSeparator = "："
    static let lineSeparator = "\n"
}
