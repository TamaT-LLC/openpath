/// メニューの操作から出すダイアログの内容。Mac 層は NSAlert に反映するだけにする。
public struct StatusItemDialog: Sendable, Equatable {
    public struct Button: Sendable, Equatable {
        public enum Role: Sendable, Equatable {
            /// 既定のボタン（Return で押せる）
            case `default`
            /// 取り消せない操作。既定のボタンとして置き、破壊的であることを示す
            case destructive
            /// キャンセル（Esc で押せる）
            case cancel
        }

        public let title: String
        public let role: Role

        public init(title: String, role: Role) {
            self.title = title
            self.role = role
        }
    }

    public let title: String
    public let message: String
    /// 左から順ではなく、NSAlert に追加する順（先頭が右端の既定のボタン）
    public let buttons: [Button]

    private static let okButton = Button(title: "OK", role: .default)
    private static let loginItemFailureTitle = "ログイン時に起動を変更できませんでした"

    /// 「履歴をクリア…」の確認。先頭のボタンを選んだらクリアする
    public static let clearHistoryConfirmation = StatusItemDialog(
        title: "履歴をクリアしますか？",
        message: "パレットの並び順に使っている履歴（使用回数と最終使用日時）をすべて削除します。この操作は取り消せません。",
        buttons: [
            Button(title: "クリア", role: .destructive),
            Button(title: "キャンセル", role: .cancel),
        ]
    )

    /// 「履歴をクリア…」で空にした履歴をファイルへ保存できなかった。
    /// パレットからは消えているが、保存できないまま終了すると次の起動で元の履歴に戻る
    public static let clearHistoryFailure = StatusItemDialog(
        title: "履歴を削除できませんでした",
        message: "履歴ファイルに書き込めませんでした。パレットからは消えましたが、書き込めないまま終了すると次の起動で元の履歴に戻ることがあります。"
            + "ディスクの空きと ~/Library/Application Support/openpath のアクセス権を確認してください。",
        buttons: [okButton]
    )

    /// ログイン時に起動の登録・解除に失敗した
    public static func loginItemFailure(_ error: LoginItemError) -> StatusItemDialog {
        StatusItemDialog(title: loginItemFailureTitle, message: error.description, buttons: [okButton])
    }

    /// .app バンドル外で動いているため、ログイン時に起動を変更できない
    public static let loginItemUnavailable = StatusItemDialog(
        title: loginItemFailureTitle,
        message: StatusMenuText.loginItemUnavailable,
        buttons: [okButton]
    )

    /// 設定ファイルを開けなかった
    public static func configFileOpenFailure(reason: String) -> StatusItemDialog {
        StatusItemDialog(title: "設定ファイルを開けませんでした", message: reason, buttons: [okButton])
    }

    /// 設定ファイルを開くアプリ（既定のアプリも、代わりに使うテキストエディットも）が見つからない
    public static let configFileApplicationNotFound = configFileOpenFailure(
        reason: "設定ファイルを開けるアプリが見つかりません。テキストエディタで直接開いてください。"
    )
}
