/// 初回起動の案内の文言（UX-001 §7）。
enum OnboardingText {
    static let windowTitle = "\(AppInfo.name) へようこそ"

    // MARK: - 権限の説明（UX-001 §7 の「何のために使うかを 3 行で」。NFR-01 / NFR-02 を伝える）

    static let explanationTitle = "アクセシビリティ権限を許可してください"
    static let explanationLines = [
        "「開く」ダイアログが出たことを検知し、その上に検索パレットを重ねるために使います。",
        "選んだ場所へダイアログを移動させるため、ダイアログにキー操作とパスを送ります。",
        "使う権限はアクセシビリティだけです。通信は行わず、パレットに打った文字も保存しません。",
    ]

    // MARK: - 権限待ち

    static let awaitingTitle = "システム設定で \(AppInfo.name) を許可してください"
    static let awaitingLines = [
        "「プライバシーとセキュリティ > アクセシビリティ」で \(AppInfo.name) をオンにしてください。",
        "一覧に無いときは、一覧の下の「+」から \(AppInfo.name).app を追加してください。",
        "許可すると自動で次へ進みます（数秒かかることがあります）。",
    ]

    // MARK: - 完了

    static let readyTitle = "準備ができました"
    static let readyLines = [
        "設定ファイルは ~/.config/\(AppInfo.name)/config.toml です。メニューバーの「設定ファイルを開く…」から編集できます。",
        "「試してみる」を押すとフォルダを選ぶダイアログが開き、\(AppInfo.name) のパレットが重なって表示されます。",
        "フォルダ名を数文字、または ~/ から始まるパスを打って Enter を押すと、ダイアログがそこへ移動します。",
    ]

    // MARK: - ボタン

    static let openSystemSettings = "システム設定を開く"
    static let openSystemSettingsAgain = "システム設定をもう一度開く"
    static let later = "あとで"
    static let tryOpenPanel = "試してみる"
    static let close = "閉じる"

    // MARK: - 「試してみる」のダイアログ

    static let trialPanelPrompt = "\(AppInfo.name) のお試し: パレットでフォルダ名を打って Enter を押すと、このダイアログがそこへ移動します。"
        + "試し終えたら「キャンセル」で閉じてください。"
}
