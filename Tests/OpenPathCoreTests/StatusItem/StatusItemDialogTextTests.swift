import Testing

import OpenPathCore

@Suite("StatusItem: ダイアログの文言")
struct StatusItemDialogTextTests {
    @Test("履歴をクリア…の確認は、消える内容と取り消せないことを伝え、クリアを破壊的な操作として示す")
    func clearHistoryConfirmation() {
        let dialog = StatusItemDialog.clearHistoryConfirmation

        #expect(dialog.title == "履歴をクリアしますか？")
        #expect(dialog.message.contains("取り消せません"))
        #expect(dialog.buttons == [
            StatusItemDialog.Button(title: "クリア", role: .destructive),
            StatusItemDialog.Button(title: "キャンセル", role: .cancel),
        ])
    }

    @Test("履歴を保存できなかった場合は、次の起動で元に戻り得ることと確認することを伝える")
    func clearHistoryFailure() {
        let dialog = StatusItemDialog.clearHistoryFailure

        #expect(dialog.title == "履歴を削除できませんでした")
        #expect(dialog.message.contains("元の履歴に戻る"))
        #expect(dialog.buttons == [StatusItemDialog.Button(title: "OK", role: .default)])
    }

    @Test("ログイン時に起動の失敗は、理由をそのまま本文にする")
    func loginItemFailure() {
        let error = LoginItemError(command: .register, underlying: LoginItemToggleTests.failure)

        let dialog = StatusItemDialog.loginItemFailure(error)

        #expect(dialog.title == "ログイン時に起動を変更できませんでした")
        #expect(dialog.message == error.description)
        #expect(dialog.buttons == [StatusItemDialog.Button(title: "OK", role: .default)])
    }

    @Test(".app 外で選ばれた場合は、設定できない理由を伝える")
    func loginItemUnavailable() {
        let dialog = StatusItemDialog.loginItemUnavailable

        #expect(dialog.title == "ログイン時に起動を変更できませんでした")
        #expect(dialog.message == "openpath.app として起動したときだけ設定できます")
    }

    @Test("設定ファイルを開けなかった場合は、理由を本文にする")
    func configFileOpenFailure() {
        let dialog = StatusItemDialog.configFileOpenFailure(reason: "設定ファイルを開くアプリが見つかりません")

        #expect(dialog.title == "設定ファイルを開けませんでした")
        #expect(dialog.message == "設定ファイルを開くアプリが見つかりません")
        #expect(dialog.buttons == [StatusItemDialog.Button(title: "OK", role: .default)])
    }

    @Test("開くアプリが見つからない場合は、直接開くよう案内する")
    func configFileApplicationNotFound() {
        let dialog = StatusItemDialog.configFileApplicationNotFound

        #expect(dialog.title == "設定ファイルを開けませんでした")
        #expect(dialog.message.contains("テキストエディタ"))
    }
}
