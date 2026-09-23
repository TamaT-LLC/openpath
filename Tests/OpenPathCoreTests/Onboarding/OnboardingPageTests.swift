import Testing

import OpenPathCore

@Suite("OnboardingPage: 初回起動の案内の文言とボタン（UX-001 §7）")
struct OnboardingPageTests {
    /// UX-001 §7「何のために使うかを 3 行で説明」
    private static let explanationLineCount = 3

    @Test("権限の説明は 3 行で、用途・アクセシビリティだけを使うこと・通信せず打った文字を保存しないことを伝える")
    func permissionExplanationLines() {
        let page = OnboardingPage.permissionExplanation

        #expect(page.messageLines.count == Self.explanationLineCount)
        #expect(page.messageLines[0].contains("「開く」ダイアログ"))
        #expect(page.messageLines[1].contains("移動"))
        #expect(page.messageLines[2].contains("アクセシビリティだけ"))
        #expect(page.messageLines[2].contains("通信"))
        #expect(page.messageLines[2].contains("保存しません"))
    }

    @Test("権限の説明は「システム設定を開く」を既定にし、「あとで」で閉じられる")
    func permissionExplanationButtons() {
        let page = OnboardingPage.permissionExplanation

        #expect(page.primaryButton == OnboardingButton(title: "システム設定を開く", command: .openSystemSettings))
        #expect(page.secondaryButton == OnboardingButton(title: "あとで", command: .close))
    }

    @Test("権限待ちは許可する場所と、許可すると自動で進むことを伝える")
    func awaitingPermission() {
        let page = OnboardingPage.awaitingPermission

        #expect(page.messageLines.contains { $0.contains("プライバシーとセキュリティ > アクセシビリティ") })
        #expect(page.messageLines.contains { $0.contains("自動で次へ進みます") })
        #expect(page.primaryButton == OnboardingButton(title: "システム設定をもう一度開く", command: .openSystemSettings))
        #expect(page.secondaryButton == OnboardingButton(title: "あとで", command: .close))
    }

    @Test("完了は設定ファイルの場所と試し方を伝え、「試してみる」を既定にする")
    func ready() {
        let page = OnboardingPage.ready

        #expect(page.messageLines.contains { $0.contains("~/.config/openpath/config.toml") })
        #expect(page.messageLines.contains { $0.contains("試してみる") })
        #expect(page.primaryButton == OnboardingButton(title: "試してみる", command: .tryOpenPanel))
        #expect(page.secondaryButton == OnboardingButton(title: "閉じる", command: .close))
    }

    @Test("どのページにも表題と本文がある", arguments: OnboardingPage.allCases)
    func everyPageHasText(page: OnboardingPage) {
        #expect(!page.title.isEmpty)
        #expect(!page.messageLines.isEmpty)
        #expect(page.messageLines.allSatisfy { !$0.isEmpty })
    }
}
