import Testing

import OpenPathCore

/// パネル判定の診断（debug ログ用、Issue #83）。どの条件で弾いたかと、子孫の要約を集める。
@Suite("OpenPanelLocator: 判定の診断（debug ログ）")
struct OpenPanelDiagnosticTests {
    private typealias Fixtures = PanelTreeFixtures

    // MARK: - いつ集めるか

    @Test("候補でないウィンドウは、初めて見たときだけ notCandidate を記録する")
    func nonCandidateWindowIsReportedOnce() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.documentWindow(id: "document"))

        let first = harness.locateDiagnosing(window)
        let second = harness.locateDiagnosing(window, at: .seconds(1))

        let entry = try #require(first.report.entries.first)
        #expect(first.report.entries.count == 1)
        #expect(entry.target == .window)
        #expect(entry.role == "AXWindow")
        #expect(entry.subrole == "AXStandardWindow")
        #expect(entry.identifier == nil)
        #expect(entry.candidateReason == nil)
        #expect(entry.result == .notCandidate)
        #expect(entry.rejectionReasons == ["notCandidate"])
        #expect(second.report.entries.isEmpty)
    }

    @Test("判定した候補は判定のたびに記録し、キャッシュが効いている間は記録しない")
    func classifiedCandidateIsReportedWhenClassified() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.dialog(id: "open", Fixtures.openPanelBody(.japanese)))

        let first = harness.locateDiagnosing(window)
        let second = harness.locateDiagnosing(window, at: .seconds(1))

        let entry = try #require(first.report.entries.first)
        #expect(first.report.entries.count == 1)
        #expect(entry.candidateReason == .dialog)
        #expect(entry.result == .openPanel)
        #expect(entry.attempt == 1)
        #expect(entry.rejectionReasons.isEmpty)
        #expect(second.report.entries.isEmpty)
    }

    @Test("シートは、ホストのウィンドウとは別に、入れ子の深さ付きで記録する")
    func sheetIsReportedSeparately() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.documentWindow(id: "safari", sheets: [
            Fixtures.remoteSheet(id: "remote", Fixtures.openPanelBody(.english, confirmTitle: "Upload")),
        ]))

        let entries = harness.locateDiagnosing(window).report.entries

        #expect(entries.map(\.target) == [.window, .sheet(nesting: 1)])
        #expect(entries.map(\.result) == [.notCandidate, .openPanel])
        #expect(entries.last?.role == "AXSheet")
        #expect(entries.last?.candidateReason == .sheet)
    }

    @Test("非モーダルの開くパネルは、AXIdentifier で候補にしたことを記録する")
    func nonModalPanelIsReportedWithIdentifier() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.nonModalPanelWindow(id: "open", Fixtures.textEditOpenPanelBody(.japanese)))

        let entry = try #require(harness.locateDiagnosing(window).report.entries.first)

        #expect(entry.subrole == "AXStandardWindow")
        #expect(entry.identifier == "open-panel")
        #expect(entry.candidateReason == .openPanelIdentifier)
        #expect(entry.result == .openPanel)
    }

    @Test("診断を集めても、判定の結果と ID は変わらない", arguments: PanelUILanguage.allCases)
    func diagnosticsDoNotChangeLookup(language: PanelUILanguage) {
        let nodes = [
            Fixtures.dialog(id: "open", Fixtures.openPanelBody(language)),
            Fixtures.nonModalPanelWindow(id: "nonModal", Fixtures.textEditOpenPanelBody(language)),
            Fixtures.dialog(id: "save", Fixtures.savePanelBody(language)),
            Fixtures.dialog(id: "alert", Fixtures.alertBody(language)),
            Fixtures.documentWindow(id: "document", sheets: [Fixtures.remoteSheet(id: "remote", Fixtures.openPanelBody(language))]),
        ]
        let plain = OpenPanelLocatorHarness()
        let diagnosing = OpenPanelLocatorHarness()
        let windows = nodes.map { node in
            plain.add(node)
            return diagnosing.add(node)
        }

        for elapsed in [Duration.zero, .milliseconds(250), .seconds(1), .seconds(4)] {
            for window in windows {
                #expect(diagnosing.locateDiagnosing(window, at: elapsed).lookup == plain.locate(window, at: elapsed))
            }
        }
    }

    @Test("診断のためだけの AX の読み取りを数える（判定のコストのログから除くため）")
    func diagnosticReadsAreCounted() {
        let plain = OpenPanelLocatorHarness()
        let diagnosing = OpenPanelLocatorHarness()
        let node = Fixtures.nonModalPanelWindow(id: "open", Fixtures.textEditOpenPanelBody(.english))
        let window = plain.add(node)
        diagnosing.add(node)

        _ = plain.locate(window)
        let report = diagnosing.locateDiagnosing(window).report

        #expect(report.diagnosticReadCount > 0)
        #expect(diagnosing.tree.reads.count - plain.tree.reads.count == report.diagnosticReadCount)
    }

    // MARK: - 弾いた条件

    @Test("「開く」を持つアラートは noFileList で、判定し直す間は pending、最後は rejected")
    func alertIsReportedAsNoFileList() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.dialog(id: "alert", Fixtures.alertBody(.japanese)))

        let attempts = [Duration.zero, .milliseconds(250), .milliseconds(750), .milliseconds(1_750), .milliseconds(3_750)]
        let entries = attempts.flatMap { harness.locateDiagnosing(window, at: $0).report.entries }

        #expect(entries.map(\.attempt) == [1, 2, 3, 4, 5])
        #expect(entries.map(\.rejectionReasons) == Array(repeating: ["noFileList"], count: 5))
        #expect(entries.dropLast().allSatisfy { $0.result == .missingElements(hasConfirmButton: true, hasFileList: false, willRecheck: true) })
        #expect(entries.last?.result == .missingElements(hasConfirmButton: true, hasFileList: false, willRecheck: false))
        #expect(harness.locateDiagnosing(window, at: .seconds(10)).report.entries.isEmpty)
    }

    @Test("確定ボタンのタイトルが一覧に無ければ noConfirmButton")
    func unknownConfirmTitleIsReported() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.dialog(id: "export", Fixtures.openPanelBody(.english, confirmTitle: "Open…")))

        let entry = try #require(harness.locateDiagnosing(window).report.entries.first)

        #expect(entry.rejectionReasons == ["noConfirmButton"])
        let details = try #require(entry.details)
        #expect(details.buttons.map(\.title).contains("Open…"))
        let hasConfirmButton = details.buttons.contains { $0.isConfirm }
        #expect(!hasConfirmButton)
    }

    @Test("保存パネルは looksLikeSavePanel で、どの入力欄のどの属性がどの語に一致したかを記録する")
    func savePanelIsReportedWithKeyword() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.dialog(id: "save", Fixtures.savePanelBody(.japanese)))

        let entry = try #require(harness.locateDiagnosing(window).report.entries.first)

        #expect(entry.result == .savePanel)
        #expect(entry.rejectionReasons == ["looksLikeSavePanel"])
        let match = try #require(entry.details?.textFields.compactMap(\.saveKeywordMatch).first)
        #expect(match == OpenPanelClassificationDetails.SaveKeywordMatch(source: .description, keyword: "名前"))
    }

    @Test("検索欄を保存欄と誤認した場合も、入力欄のサブロールで分かる")
    func searchFieldMisreadAsSaveFieldIsVisible() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.dialog(id: "open", [
            Fixtures.group([Fixtures.textField(description: "名前で検索", subrole: "AXSearchField")]),
            Fixtures.group([Fixtures.fileList(role: "AXOutline")]),
            Fixtures.button("開く"),
        ]))

        let entry = try #require(harness.locateDiagnosing(window).report.entries.first)

        #expect(entry.rejectionReasons == ["looksLikeSavePanel"])
        let field = try #require(entry.details?.textFields.first)
        #expect(field.subrole == "AXSearchField")
        #expect(field.hasDescription)
        #expect(field.saveKeywordMatch?.keyword == "名前")
    }

    @Test("ファイル一覧が探索の深さの上限より深ければ、noFileList に truncated を添える")
    func fileListBeyondDepthLimitIsTruncated() throws {
        let harness = OpenPanelLocatorHarness()
        let deepList = (0 ..< 6).reduce(Fixtures.fileList(role: "AXBrowser")) { inner, _ in Fixtures.group([inner]) }
        let window = harness.add(Fixtures.dialog(id: "deep", [deepList, Fixtures.button("開く")]))

        let entry = try #require(harness.locateDiagnosing(window).report.entries.first)

        #expect(entry.rejectionReasons == ["noFileList", "truncated"])
        let details = try #require(entry.details)
        #expect(details.deepestLevel == BoundedBreadthFirstSearch.defaultMaxDepth)
        #expect(details.unexploredAtDepthLimit == 1)
        #expect(details.isTruncated)
    }

    @Test("訪問する要素の数の上限に達したら truncated")
    func visitLimitIsTruncated() throws {
        let harness = OpenPanelLocatorHarness()
        let filler = (0 ..< BoundedBreadthFirstSearch.defaultMaxVisitedNodes).map { _ in StubNode(role: "AXStaticText") }
        let window = harness.add(Fixtures.dialog(id: "crowded", filler + [
            Fixtures.fileList(role: "AXOutline"),
            Fixtures.button("開く"),
        ]))

        let entry = try #require(harness.locateDiagnosing(window).report.entries.first)

        #expect(entry.rejectionReasons == ["noConfirmButton", "noFileList", "truncated"])
        #expect(entry.details?.visitedCount == BoundedBreadthFirstSearch.defaultMaxVisitedNodes)
    }

    @Test("上限の深さにある要素でも、子が無ければ truncated にしない")
    func leafAtDepthLimitIsNotTruncated() throws {
        let harness = OpenPanelLocatorHarness()
        let deepLeaf = (0 ..< 5).reduce(StubNode(role: "AXStaticText")) { inner, _ in Fixtures.group([inner]) }
        let window = harness.add(Fixtures.dialog(id: "alert", [deepLeaf, Fixtures.button("開く")]))

        let entry = try #require(harness.locateDiagnosing(window).report.entries.first)

        #expect(entry.rejectionReasons == ["noFileList"])
        #expect(entry.details?.unexploredAtDepthLimit == 0)
    }

    @Test("候補の中身を読めなければ unreadable を候補ごとに 1 回だけ記録し、探索の結果は変えない")
    func unreadableCandidateIsReportedOnce() throws {
        let plain = OpenPanelLocatorHarness()
        let diagnosing = OpenPanelLocatorHarness()
        let node = Fixtures.nonModalPanelWindow(id: "open", Fixtures.openPanelBody(.japanese))
        let window = plain.add(node)
        diagnosing.add(node)
        // リモートビューの中身を読めない（応答のタイムアウトなど）
        plain.tree.failures[StubElement("open/0")] = .unavailable
        diagnosing.tree.failures[StubElement("open/0")] = .unavailable

        let first = diagnosing.locateDiagnosing(window)
        let second = diagnosing.locateDiagnosing(window, at: .milliseconds(200))

        #expect(first.lookup == plain.locate(window))
        #expect(first.lookup == .undetermined(lastKnown: nil))
        let entry = try #require(first.report.entries.first)
        #expect(first.report.entries.count == 1)
        #expect(entry.candidateReason == .openPanelIdentifier)
        #expect(entry.result == .unreadable)
        #expect(entry.rejectionReasons == ["unreadable"])
        #expect(entry.logMessage.contains("candidate: openPanelIdentifier, attempt: 1/5, result: undetermined: unreadable)"))
        #expect(second.report.entries.isEmpty)
    }

    // MARK: - 子孫の要約

    @Test("子孫の要約: ボタンの表題と有効状態、一覧の role・subrole、入力欄の説明・タイトルの有無、role の数")
    func detailsSummarizeDescendants() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.dialog(id: "open", [
            Fixtures.group([
                Fixtures.textField(description: "検索", subrole: "AXSearchField"),
                StubNode(role: "AXButton", description: "戻る", isEnabled: false),
                StubNode(role: "AXButton", description: "開く", isEnabled: true),
            ]),
            Fixtures.group([
                StubNode(role: "AXOutline", subrole: "AXSourceList"),
                StubNode(role: "AXList", subrole: "AXCollectionList"),
                StubNode(role: "AXList", subrole: "AXSectionList"),
            ]),
            StubNode(role: "AXButton", title: "キャンセル", isEnabled: true),
            StubNode(role: "AXButton", title: "開く", isEnabled: false),
        ]))

        let details = try #require(harness.locateDiagnosing(window).report.entries.first?.details)

        #expect(details.buttons == [
            .init(title: "キャンセル", isEnabled: true, hasDescription: false, descriptionConfirmTitle: nil),
            .init(title: "開く", isEnabled: false, hasDescription: false, descriptionConfirmTitle: nil),
            .init(title: nil, isEnabled: false, hasDescription: true, descriptionConfirmTitle: nil),
            .init(title: nil, isEnabled: true, hasDescription: true, descriptionConfirmTitle: "開く"),
        ])
        #expect(details.lists == [
            .init(role: "AXOutline", subrole: "AXSourceList", isFileList: true),
            .init(role: "AXList", subrole: "AXCollectionList", isFileList: true),
            .init(role: "AXList", subrole: "AXSectionList", isFileList: false),
        ])
        #expect(details.textFields == [
            .init(subrole: "AXSearchField", hasDescription: true, hasTitle: false, saveKeywordMatch: nil),
        ])
        #expect(details.roleCounts["AXButton"] == 4)
        #expect(details.roleCounts["AXGroup"] == 2)
        #expect(details.visitedCount == 10)
        #expect(details.deepestLevel == 2)
    }
}
