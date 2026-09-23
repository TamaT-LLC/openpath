import Testing

import OpenPathCore

@Suite("InjectionError: パレットに出す文言")
struct InjectionErrorTests {
    /// kAXErrorCannotComplete
    private static let axCannotCompleteCode: Int32 = -25_204

    @Test(
        "エラー種別ごとにフッターの文言を返す（UX-001 §5, DSN-001 §3.3）",
        arguments: [
            (InjectionError.timeout(step: .waitSheet), "移動できませんでした（⌘⇧G が開きません）"),
            (InjectionError.timeout(step: .waitPaste), "移動できませんでした（パスの貼り付けに失敗）"),
            (InjectionError.timeout(step: .overall), "移動できませんでした（タイムアウト）"),
            (InjectionError.axError(code: axCannotCompleteCode), "移動できませんでした（アクセシビリティ操作に失敗 (-25204)）"),
            // パネルの移動は済んでいる場合があるため「移動できませんでした」とは言わない
            (InjectionError.pasteboardRestoreFailed, "クリップボードを元に戻せませんでした"),
        ]
    )
    func userMessage(error: InjectionError, expected: String) {
        #expect(error.userMessage == expected)
    }

    @Test("パネル消滅時はパレットを閉じるため文言を持たない")
    func panelGoneHasNoMessage() {
        #expect(InjectionError.panelGone.userMessage == nil)
    }

    @Test("注入中・汎用失敗の文言")
    func paletteMessages() {
        #expect(PaletteMessage.injecting == "パネルへ移動中…")
        #expect(PaletteMessage.injectionFailed == "移動できませんでした")
    }
}
