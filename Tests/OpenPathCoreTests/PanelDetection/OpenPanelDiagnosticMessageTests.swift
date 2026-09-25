import Testing

import OpenPathCore

/// パネル判定の診断の debug ログの文言（Issue #83）。パス・ファイル名・ウィンドウタイトルの本文は出さない。
@Suite("PanelWatchLogMessage: パネル判定の診断の文言")
struct OpenPanelDiagnosticMessageTests {
    private typealias Fixtures = PanelTreeFixtures

    private static func firstEntry(_ node: StubNode) throws -> OpenPanelDiagnostic {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(node)
        return try #require(harness.locateDiagnosing(window).report.entries.first)
    }

    // MARK: - ウィンドウ・候補ごとの 1 行

    @Test("候補でないウィンドウの 1 行")
    func notCandidateMessage() throws {
        let entry = try Self.firstEntry(Fixtures.documentWindow(id: "document"))

        #expect(entry.logMessage
            == "panel check (target: window, role: AXWindow, subrole: AXStandardWindow, identifier: none, result: rejected: notCandidate)")
    }

    @Test("判定した候補の 1 行")
    func classifiedMessage() throws {
        let entry = try Self.firstEntry(Fixtures.dialog(id: "open", [
            Fixtures.group([StubNode(role: "AXOutline")]),
            Fixtures.button("開く"),
        ]))

        #expect(entry.logMessage == "panel check (target: window, role: AXWindow, subrole: AXDialog, identifier: none, "
            + "candidate: dialog, attempt: 1/5, result: openPanel, buttons: [開く*(enabled: ?)], lists: [AXOutline*], "
            + "textFields: [], search: (visited: 3/400, deepest: 2/6, unexploredAtDepthLimit: 0), "
            + "roles: AXButton×1 AXGroup×1 AXOutline×1)")
    }

    @Test("判定し直す予定の候補は pending、弾いた条件と truncated を並べる")
    func pendingMessage() throws {
        let deepList = (0 ..< 6).reduce(Fixtures.fileList(role: "AXBrowser")) { inner, _ in Fixtures.group([inner]) }
        let entry = try Self.firstEntry(Fixtures.dialog(id: "deep", [deepList]))

        #expect(entry.logMessage.contains("attempt: 1/5, result: pending: noConfirmButton+noFileList+truncated,"))
        #expect(entry.logMessage.contains("unexploredAtDepthLimit: 1"))
    }

    @Test("非モーダルの開くパネルの 1 行には、AXIdentifier と候補にした理由が出る")
    func nonModalMessage() throws {
        let entry = try Self.firstEntry(Fixtures.nonModalPanelWindow(id: "open", Fixtures.textEditOpenPanelBody(.japanese)))

        #expect(entry.logMessage.hasPrefix(
            "panel check (target: window, role: AXWindow, subrole: AXStandardWindow, identifier: open-panel, candidate: openPanelIdentifier,"
        ))
        #expect(entry.logMessage.contains("result: openPanel,"))
        #expect(entry.logMessage.contains("開く*(enabled: ?)"))
        #expect(entry.logMessage.contains("オプションを表示(enabled: ?)"))
        #expect(entry.logMessage.contains("textFields: [AXSearchField(desc: yes, title: no)]"))
    }

    @Test("シートの 1 行は、入れ子の深さを target に出す")
    func sheetMessage() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.documentWindow(id: "host", sheets: [Fixtures.sheet(id: "sheet", Fixtures.alertBody(.english))]))

        let messages = harness.locateDiagnosing(window).report.entries.map(\.logMessage)

        #expect(messages.count == 2)
        #expect(messages.last?.hasPrefix("panel check (target: sheet#1, role: AXSheet, subrole: none, identifier: none, candidate: sheet,") == true)
    }

    @Test("保存パネルの 1 行には、一致した語と属性を出し、入力欄の文字列は出さない")
    func savePanelMessage() throws {
        let entry = try Self.firstEntry(Fixtures.dialog(id: "save", [
            Fixtures.textField(description: "保存先 /Users/someone/Documents/秘密.txt"),
            Fixtures.group([Fixtures.fileList(role: "AXOutline")]),
            Fixtures.button("保存"),
        ]))

        #expect(entry.logMessage.contains("result: rejected: looksLikeSavePanel,"))
        #expect(entry.logMessage.contains("textFields: [AXTextField(desc: yes, title: no, saveKeyword: 保存 in desc)]"))
        #expect(!entry.logMessage.contains("/Users"))
        #expect(!entry.logMessage.contains("秘密"))
    }

    @Test("ウィンドウタイトル・入力欄の文字列・よく使う表題でないボタンの表題は出さない")
    func privateStringsAreNotLogged() throws {
        var window = Fixtures.dialog(id: "open", [
            Fixtures.textField(description: "検索: 秘密のプロジェクト", title: "~/Projects/secret", subrole: "AXSearchField"),
            Fixtures.group([Fixtures.fileList(role: "AXOutline")]),
            Fixtures.button("/Users/someone/秘密.txt"),
            Fixtures.button("README"),
            Fixtures.button("「書類.txt」を開く"),
            Fixtures.button("開く"),
        ])
        window.title = "秘密の書類.txt — /Users/someone"
        let entry = try Self.firstEntry(window)

        for secret in ["/Users", "秘密", "~/Projects", "secret", "README", "書類"] {
            #expect(!entry.logMessage.contains(secret), "\(secret)")
        }
        #expect(entry.logMessage.contains(
            "buttons: [<other len: 21>(enabled: ?), <other len: 6>(enabled: ?), <other len: 11, contains: 開く>(enabled: ?), 開く*(enabled: ?)]"
        ))
    }

    @Test(
        "パネルでよく使う表題は、そのまま出す",
        arguments: [
            "開く", "Open", "選択", "Choose", "追加", "Add", "アップロード", "Upload",
            "キャンセル", "Cancel", "新規フォルダ", "New Folder", "新規書類", "New Document",
            "オプションを表示", "Show Options", "オプションを隠す", "Hide Options", "保存", "Save", "移動", "Go", "完了", "Done",
        ]
    )
    func knownTitlesAreLogged(title: String) throws {
        let entry = try Self.firstEntry(Fixtures.dialog(id: "open", [Fixtures.button(title)]))
        let mark = OpenPanelCriteria.isConfirmButtonTitle(title) ? "*" : ""

        #expect(entry.logMessage.contains("buttons: [\(title)\(mark)(enabled: ?)]"))
    }

    @Test(
        "よく使う表題でなければ、長さと、含む確定ボタンの表題（大文字小文字は区別しない）だけを出す",
        arguments: [
            ("開く…", "<other len: 3, contains: 開く>"),
            ("Open...", "<other len: 7, contains: Open>"),
            ("open file", "<other len: 9, contains: Open>"),
            ("  開く  ", "開く"),
            ("Ver. 2", "<other len: 6>"),
            ("Line one\nline two", "<other len: 17>"),
        ]
    )
    func otherTitlesAreClassified(title: String, expected: String) throws {
        let entry = try Self.firstEntry(Fixtures.dialog(id: "open", [Fixtures.button(title)]))

        #expect(entry.logMessage.contains("buttons: [\(expected)"), "\(entry.logMessage)")
    }

    @Test("ボタンは 12 個まで並べ、超える分は数だけ出す")
    func buttonCountIsBounded() throws {
        let buttons = (1 ... 14).map { Fixtures.button("Button \($0)") } + [Fixtures.button("キャンセル"), Fixtures.button("開く")]
        let entry = try Self.firstEntry(Fixtures.dialog(id: "many", buttons))

        #expect(entry.logMessage.contains("<other len: 9>(enabled: ?), +4 more]"))
        #expect(!entry.logMessage.contains("Button 1"))
    }

    @Test("表題の無いボタンは説明の有無だけを出し、説明が確定ボタンの表題と一致するときだけその表題を出す")
    func untitledButtons() throws {
        let entry = try Self.firstEntry(Fixtures.dialog(id: "open", [
            StubNode(role: "AXButton", description: "戻る", isEnabled: true),
            StubNode(role: "AXButton", description: "開く", isEnabled: false),
            StubNode(role: "AXButton"),
        ]))

        #expect(entry.logMessage.contains(
            "buttons: [-(desc: yes, enabled: true), -(desc: 開く*, enabled: false), -(desc: no, enabled: ?)]"
        ))
        #expect(!entry.logMessage.contains("戻る"))
    }

    // MARK: - 観測と走査の要約

    @Test("走査の要約: プロセス ID、bundle id、ウィンドウ数")
    func scanSummaryMessage() {
        let found = PanelScanSummary(processID: 4_321, bundleIdentifier: "com.apple.TextEdit", windowCount: 2, axErrorCode: nil)
        let unavailable = PanelScanSummary(processID: 4_321, bundleIdentifier: nil, windowCount: nil, axErrorCode: -25_204)

        #expect(PanelWatchLogMessage.scanSummary(found) == "panel scan (pid: 4321, bundleId: com.apple.TextEdit, windows: 2)")
        #expect(PanelWatchLogMessage.scanSummary(unavailable)
            == "panel scan (pid: 4321, bundleId: none, windows: unavailable, axError: -25204)")
    }

    @Test("走査の要約は、直前に出したものと変わったときだけ出す")
    func scanSummaryIsLoggedOnChange() {
        var log = PanelScanSummaryLog()
        let one = PanelScanSummary(processID: 1, bundleIdentifier: "a", windowCount: 1, axErrorCode: nil)
        let two = PanelScanSummary(processID: 1, bundleIdentifier: "a", windowCount: 2, axErrorCode: nil)
        let otherApp = PanelScanSummary(processID: 2, bundleIdentifier: "b", windowCount: 2, axErrorCode: nil)

        #expect(log.messageIfChanged(one) == PanelWatchLogMessage.scanSummary(one))
        #expect(log.messageIfChanged(one) == nil)
        #expect(log.messageIfChanged(two) == PanelWatchLogMessage.scanSummary(two))
        #expect(log.messageIfChanged(otherApp) == PanelWatchLogMessage.scanSummary(otherApp))
        #expect(log.messageIfChanged(one) == PanelWatchLogMessage.scanSummary(one))
    }

    @Test("観測の張り付け・失敗・通知の文言")
    func observationMessages() {
        #expect(PanelWatchLogMessage.attached(processID: 4_321, bundleIdentifier: "com.apple.TextEdit")
            == "panel watch attached (pid: 4321, bundleId: com.apple.TextEdit)")
        #expect(PanelWatchLogMessage.observationFailed(processID: 4_321, bundleIdentifier: nil, axErrorCode: -25_204, step: "AXWindowCreated")
            == "panel watch observer failed (pid: 4321, bundleId: none, axError: -25204, step: AXWindowCreated)")
        #expect(PanelWatchLogMessage.notificationReceived(processID: 4_321, notification: "AXWindowCreated")
            == "panel watch notification (pid: 4321, notification: AXWindowCreated)")
    }
}
