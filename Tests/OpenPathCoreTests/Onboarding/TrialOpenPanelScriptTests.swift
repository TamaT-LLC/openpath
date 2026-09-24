import Testing

@testable import OpenPathCore

@Suite("TrialOpenPanelScript: 「試してみる」で出す「開く」ダイアログ")
struct TrialOpenPanelScriptTests {
    @Test("osascript の choose folder で、案内の文言を添えたフォルダ選択のダイアログを出す")
    func arguments() {
        #expect(TrialOpenPanelScript.executablePath == "/usr/bin/osascript")
        #expect(TrialOpenPanelScript.arguments == [
            "-e",
            "choose folder with prompt " + AppleScriptLiteral.string(TrialOpenPanelScript.prompt),
        ])
    }

    @Test("他のアプリへ命令を送らない（tell を含まない）ため、オートメーションの許可を求めない")
    func doesNotTargetOtherApplications() {
        let script = TrialOpenPanelScript.arguments.joined(separator: " ")

        #expect(!script.contains("tell"))
    }

    @Test(
        "AppleScript の文字列リテラルでは、引用符とバックスラッシュをエスケープする",
        arguments: [
            ("フォルダ", "\"フォルダ\""),
            ("a\"b", "\"a\\\"b\""),
            ("a\\b", "\"a\\\\b\""),
            ("\\\"", "\"\\\\\\\"\""),
            ("", "\"\""),
        ]
    )
    func stringLiteral(text: String, expected: String) {
        #expect(AppleScriptLiteral.string(text) == expected)
    }
}
