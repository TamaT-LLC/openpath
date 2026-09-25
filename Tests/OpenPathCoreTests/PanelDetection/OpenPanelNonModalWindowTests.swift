import Testing

import OpenPathCore

/// 非モーダルの NSOpenPanel（TextEdit の「ファイル > 開く…」など）の検出（Issue #83）。
///
/// NSDocumentController の「開く…」は非モーダル（`beginOpenPanel`）で、パネルのウィンドウのサブロールは AXDialog ではなく
/// AXStandardWindow になる。AXIdentifier の `open-panel` で候補にする。
@Suite("OpenPanelLocator: 非モーダルの NSOpenPanel（AXIdentifier が open-panel の通常のウィンドウ）")
struct OpenPanelNonModalWindowTests {
    private typealias Fixtures = PanelTreeFixtures
    private typealias Read = StubPanelTree.Read

    // MARK: - 候補の条件

    @Test("AXIdentifier が open-panel のウィンドウは、サブロールに関わらず候補にする")
    func openPanelIdentifierMakesCandidate() {
        #expect(OpenPanelCriteria.isPanelCandidate(role: "AXWindow", subrole: "AXStandardWindow", identifier: "open-panel"))
        #expect(OpenPanelCriteria.isPanelCandidate(role: "AXWindow", subrole: nil, identifier: "open-panel"))
        #expect(OpenPanelCriteria.candidateReason(role: "AXWindow", subrole: "AXStandardWindow", identifier: "open-panel")
            == .openPanelIdentifier)
    }

    @Test(
        "open-panel 以外の AXIdentifier の通常のウィンドウは候補にしない",
        arguments: [nil, "save-panel", "Open-Panel", "open-panel-2", ""] as [String?]
    )
    func otherIdentifiersAreNotCandidates(identifier: String?) {
        #expect(!OpenPanelCriteria.isPanelCandidate(role: "AXWindow", subrole: "AXStandardWindow", identifier: identifier))
        #expect(OpenPanelCriteria.candidateReason(role: "AXWindow", subrole: "AXStandardWindow", identifier: identifier) == nil)
    }

    @Test("これまでの候補（シート・ダイアログ）は、AXIdentifier が無くても候補のまま")
    func existingCandidatesAreKept() {
        #expect(OpenPanelCriteria.candidateReason(role: "AXSheet", subrole: nil, identifier: nil) == .sheet)
        #expect(OpenPanelCriteria.candidateReason(role: "AXWindow", subrole: "AXSheet", identifier: nil) == .sheet)
        #expect(OpenPanelCriteria.candidateReason(role: "AXWindow", subrole: "AXDialog", identifier: nil) == .dialog)
        #expect(OpenPanelCriteria.candidateReason(role: "AXWindow", subrole: "AXDialog", identifier: "open-panel") == .dialog)
        #expect(OpenPanelCriteria.isPanelCandidate(role: "AXWindow", subrole: "AXDialog"))
    }

    // MARK: - 検出

    @Test("TextEdit の「開く」パネル（非モーダル・リモートビュー）を見つける", arguments: PanelUILanguage.allCases)
    func textEditOpenPanelIsFound(language: PanelUILanguage) throws {
        let harness = OpenPanelLocatorHarness()
        let document = harness.add(Fixtures.documentWindow(id: "document"))
        let panelWindow = harness.add(Fixtures.nonModalPanelWindow(id: "open", Fixtures.textEditOpenPanelBody(language)))

        #expect(harness.locate(document) == .notFound)
        let panel = try #require(harness.panel(in: panelWindow))

        #expect(panel.element == panelWindow)
        #expect(panel.context.frame == Fixtures.dialogFrame)
        #expect(panel.isNewlyClassified)
    }

    @Test("非モーダルのパネルの ID は、走査し直しても変わらない")
    func nonModalPanelIDIsStable() throws {
        let harness = OpenPanelLocatorHarness()
        let panelWindow = harness.add(Fixtures.nonModalPanelWindow(id: "open", Fixtures.openPanelBody(.japanese)))

        let first = try #require(harness.panel(in: panelWindow))
        let second = try #require(harness.panel(in: panelWindow, at: .seconds(1)))

        #expect(second.context.id == first.context.id)
        #expect(!second.isNewlyClassified)
    }

    @Test("非モーダルの保存パネル（AXIdentifier が save-panel）は見つからない", arguments: PanelUILanguage.allCases)
    func nonModalSavePanelIsNotFound(language: PanelUILanguage) {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.nonModalPanelWindow(id: "save", identifier: "save-panel", Fixtures.savePanelBody(language)))

        #expect(harness.locate(window) == .notFound)
        // 候補でないウィンドウは判定しない（中身を読まない）
        #expect(harness.tree.readCount(of: .title) == 0)
    }

    @Test("AXIdentifier が open-panel でも、保存パネルの中身なら見つからない（条件 4 は変えない）")
    func openPanelIdentifierWithSaveBodyIsRejected() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.nonModalPanelWindow(id: "save", Fixtures.savePanelBody(.japanese)))

        #expect(harness.locate(window) == .notFound)
    }

    // MARK: - AX の読み取り

    @Test("AXIdentifier は候補でないウィンドウでだけ、ウィンドウごとに 1 回だけ読む")
    func identifierIsReadOncePerNonCandidateWindow() {
        let harness = OpenPanelLocatorHarness()
        let document = harness.add(Fixtures.documentWindow(id: "document"))
        let dialog = harness.add(Fixtures.dialog(id: "dialog", Fixtures.openPanelBody(.english)))
        let sheetHost = harness.add(Fixtures.documentWindow(id: "host", sheets: [
            Fixtures.sheet(id: "sheet", Fixtures.openPanelBody(.english)),
        ]))

        for elapsed in [Duration.zero, .seconds(1), .seconds(2)] {
            _ = harness.locate(document, at: elapsed)
            _ = harness.locate(dialog, at: elapsed)
            _ = harness.locate(sheetHost, at: elapsed)
        }

        let identifierReads = harness.tree.reads.filter { $0.attribute == .identifier }.map(\.element)
        #expect(identifierReads == [document, sheetHost])
    }

    @Test("キャッシュが効いた後の非モーダルのパネルの走査は、矩形の読み取りだけ")
    func cachedNonModalPanelReadsOnlyFrame() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.nonModalPanelWindow(id: "open", Fixtures.openPanelBody(.japanese)))
        _ = harness.locate(window)
        harness.tree.resetReads()

        // 選択モードの推定し直し（行を読めなかった場合、250ms 後）より前に走査する
        _ = harness.locate(window, at: .milliseconds(200))

        #expect(harness.tree.reads == [Read(element: window, attribute: .frame)])
    }

    @Test("非モーダルのパネルの中身が描画途中なら、判定し直して見つける")
    func nonModalPanelRenderedLaterIsFound() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.nonModalPanelWindow(id: "open", []))
        #expect(harness.locate(window) == .notFound)

        harness.tree.replace(Fixtures.nonModalPanelWindow(id: "open", Fixtures.openPanelBody(.japanese)))

        #expect(harness.panel(in: window, at: .milliseconds(250))?.element == window)
    }
}
