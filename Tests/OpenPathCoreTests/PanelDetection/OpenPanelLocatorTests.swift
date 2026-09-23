import CoreGraphics
import Testing

import OpenPathCore

@Suite("OpenPanelLocator: ウィンドウからのパネルの検出と ID")
struct OpenPanelLocatorTests {
    private typealias Fixtures = PanelTreeFixtures

    /// パネルでないウィンドウ。
    enum NonPanelWindow: String, CaseIterable, CustomStringConvertible {
        case saveDialog
        case saveSheet
        case alertDialog
        case alertSheet
        case documentWindow

        var description: String {
            rawValue
        }

        func node(_ language: PanelUILanguage) -> StubNode {
            switch self {
            case .saveDialog:
                Fixtures.dialog(id: "window", Fixtures.savePanelBody(language))
            case .saveSheet:
                Fixtures.documentWindow(id: "window", sheets: [Fixtures.sheet(id: "sheet", Fixtures.savePanelBody(language))])
            case .alertDialog:
                Fixtures.dialog(id: "window", Fixtures.alertBody(language))
            case .alertSheet:
                Fixtures.documentWindow(id: "window", sheets: [Fixtures.sheet(id: "sheet", Fixtures.alertBody(language))])
            case .documentWindow:
                Fixtures.documentWindow(id: "window")
            }
        }
    }

    // MARK: - 検出

    @Test("ダイアログの NSOpenPanel を見つける（パネルの要素はウィンドウ自身）", arguments: PanelUILanguage.allCases)
    func dialogPanelIsFound(language: PanelUILanguage) throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.dialog(id: "open", Fixtures.openPanelBody(language)))

        let panel = try #require(harness.panel(in: window))

        #expect(panel.element == window)
        #expect(panel.context.frame == Fixtures.dialogFrame)
        #expect(!panel.context.isDirectoriesOnly)
        #expect(panel.isNewlyClassified)
    }

    @Test("ウィンドウの子のシートの NSOpenPanel を見つける（パネルの要素はシート）", arguments: PanelUILanguage.allCases)
    func sheetPanelIsFound(language: PanelUILanguage) throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.documentWindow(id: "document", sheets: [
            Fixtures.sheet(id: "sheet", Fixtures.openPanelBody(language)),
        ]))

        let panel = try #require(harness.panel(in: window))

        #expect(panel.element == StubElement("sheet"))
        #expect(panel.context.frame == Fixtures.sheetFrame)
    }

    @Test(
        "サンドボックスアプリのパネル（Safari のファイル選択など）を見つける",
        arguments: [("アップロード", PanelUILanguage.japanese), ("Upload", .english), ("開く", .japanese)]
    )
    func sandboxedPanelIsFound(confirmTitle: String, language: PanelUILanguage) throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.documentWindow(id: "safari", sheets: [
            Fixtures.remoteSheet(id: "remote", Fixtures.openPanelBody(language, confirmTitle: confirmTitle)),
        ]))

        #expect(harness.panel(in: window)?.element == StubElement("remote"))
    }

    @Test("ウィンドウ一覧にシートそのものが含まれていても見つける")
    func topLevelSheetIsFound() throws {
        let harness = OpenPanelLocatorHarness()
        let sheet = harness.add(Fixtures.sheet(id: "sheet", Fixtures.openPanelBody(.japanese)))

        #expect(harness.panel(in: sheet)?.element == sheet)
    }

    @Test(
        "保存パネル・アラート・通常のウィンドウでは見つからない",
        arguments: NonPanelWindow.allCases, PanelUILanguage.allCases
    )
    func nonPanelWindowsAreNotFound(window: NonPanelWindow, language: PanelUILanguage) {
        let harness = OpenPanelLocatorHarness()
        let element = harness.add(window.node(language))

        #expect(harness.locate(element) == .notFound)
    }

    @Test("通常のウィンドウは、ファイル一覧と「開く」ボタンを持っていても候補にしない（Finder のウィンドウなど）")
    func standardWindowIsNotCandidate() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(StubNode(
            id: "finder",
            role: "AXWindow",
            subrole: "AXStandardWindow",
            children: Fixtures.openPanelBody(.japanese)
        ))

        #expect(harness.locate(window) == .notFound)
        #expect(harness.tree.readCount(of: .title) == 0)
    }

    @Test("開くパネルでないダイアログに付いたシートの NSOpenPanel も見つける")
    func sheetOnNonPanelDialogIsFound() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.dialog(id: "settings", Fixtures.alertBody(.english) + [
            Fixtures.sheet(id: "sheet", Fixtures.openPanelBody(.english)),
        ]))

        #expect(harness.panel(in: window)?.element == StubElement("sheet"))
    }

    @Test("開くパネルでないダイアログに付いたシートのパネルを閉じたら、見つからなくなる")
    func closedSheetOnNonPanelDialogIsGone() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.dialog(id: "settings", Fixtures.alertBody(.english) + [
            Fixtures.sheet(id: "sheet", Fixtures.openPanelBody(.english)),
        ]))
        _ = harness.locate(window)

        harness.tree.replace(Fixtures.dialog(id: "settings", Fixtures.alertBody(.english)))

        #expect(harness.locate(window, at: .milliseconds(200)) == .notFound)
    }

    @Test("シートの子のシートにある NSOpenPanel も見つける（リモートビューがシートを重ねる場合に備える）")
    func nestedSheetPanelIsFound() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.documentWindow(id: "document", sheets: [
            Fixtures.sheet(id: "host", [Fixtures.remoteSheet(id: "inner", Fixtures.openPanelBody(.japanese))]),
        ]))

        #expect(harness.panel(in: window)?.element == StubElement("inner"))
    }

    @Test("シートの入れ子は 2 段までしか探さない")
    func sheetNestingIsBounded() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.documentWindow(id: "document", sheets: [
            Fixtures.sheet(id: "first", [Fixtures.sheet(id: "second", [
                Fixtures.sheet(id: "third", Fixtures.openPanelBody(.japanese)),
            ])]),
        ]))

        #expect(harness.locate(window) == .notFound)
        #expect(!harness.didClassify(StubElement("third")))
    }

    @Test("ダイアログが開くパネルなら、子のシート（⌘⇧G の移動先シート）は判定しない")
    func goToSheetOnDialogPanelIsNotClassified() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.dialog(id: "open", Fixtures.openPanelBody(.japanese) + [
            Fixtures.sheet(id: "go-to", Fixtures.goToSheet(.japanese).children),
        ]))

        #expect(harness.panel(in: window)?.element == window)
        #expect(!harness.didClassify(StubElement("go-to")))
    }

    @Test("矩形を取得できなければ .zero にする")
    func missingFrameIsZero() {
        let harness = OpenPanelLocatorHarness()
        var dialog = Fixtures.dialog(id: "open", Fixtures.openPanelBody(.japanese))
        dialog.frame = nil
        let window = harness.add(dialog)

        #expect(harness.panel(in: window)?.context.frame == .zero)
    }

    // MARK: - ID の安定性

    @Test("同じパネルは何度探しても同じ ID になり、2 回目以降は判定し直さない")
    func sameIDAcrossScans() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.dialog(id: "open", Fixtures.openPanelBody(.japanese)))

        let first = try #require(harness.panel(in: window))
        let second = try #require(harness.panel(in: window, at: .milliseconds(200)))

        #expect(second.context.id == first.context.id)
        #expect(!second.isNewlyClassified)
    }

    @Test("ダイアログのパネルは ⌘⇧G で移動先シートを出し、フォルダを移動しても ID が変わらない")
    func dialogIDSurvivesGoToFolder() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.dialog(id: "open", Fixtures.openPanelBody(.japanese)))
        let before = try #require(harness.panel(in: window))

        harness.tree.replace(Fixtures.dialog(id: "open", Fixtures.openPanelBody(.japanese) + [Fixtures.goToSheet(.japanese)]))
        let whileGoTo = try #require(harness.panel(in: window, at: .milliseconds(200)))
        harness.tree.replace(Fixtures.dialog(id: "open", Fixtures.openPanelBody(.japanese, fileListRole: "AXOutline")))
        let afterMove = try #require(harness.panel(in: window, at: .milliseconds(400)))

        #expect(whileGoTo.context.id == before.context.id)
        #expect(afterMove.context.id == before.context.id)
    }

    @Test("シートのパネルは ⌘⇧G で移動先シートを出し、フォルダを移動しても ID が変わらない")
    func sheetIDSurvivesGoToFolder() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.documentWindow(id: "document", sheets: [
            Fixtures.remoteSheet(id: "panel", Fixtures.openPanelBody(.english)),
        ]))
        let before = try #require(harness.panel(in: window))

        harness.tree.replace(Fixtures.documentWindow(id: "document", sheets: [
            Fixtures.remoteSheet(id: "panel", Fixtures.openPanelBody(.english) + [Fixtures.goToSheet(.english)]),
        ]))
        let whileGoTo = try #require(harness.panel(in: window, at: .milliseconds(200)))

        #expect(whileGoTo.context.id == before.context.id)
        #expect(whileGoTo.element == before.element)
    }

    @Test("パネルが動いたら、同じ ID のまま矩形を更新する")
    func movedPanelKeepsIDWithNewFrame() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.dialog(id: "open", Fixtures.openPanelBody(.japanese)))
        let before = try #require(harness.panel(in: window))
        let movedFrame = Fixtures.dialogFrame.offsetBy(dx: 40, dy: 30)

        harness.tree.replace(Fixtures.dialog(id: "open", frame: movedFrame, Fixtures.openPanelBody(.japanese)))
        let after = try #require(harness.panel(in: window, at: .milliseconds(200)))

        #expect(after.context.id == before.context.id)
        #expect(after.context.frame == movedFrame)
    }

    @Test("別のパネルには別の ID を振る")
    func differentPanelsHaveDifferentIDs() throws {
        let harness = OpenPanelLocatorHarness()
        let first = harness.add(Fixtures.dialog(id: "first", Fixtures.openPanelBody(.japanese)))
        let second = harness.add(Fixtures.dialog(id: "second", Fixtures.openPanelBody(.english)))

        let firstID = try #require(harness.panel(in: first)?.context.id)
        let secondID = try #require(harness.panel(in: second)?.context.id)

        #expect(firstID != secondID)
    }

    @Test("シートのパネルを閉じて開き直したら、新しい ID を振る")
    func reopenedSheetPanelGetsNewID() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.documentWindow(id: "document", sheets: [
            Fixtures.sheet(id: "panel-1", Fixtures.openPanelBody(.japanese)),
        ]))
        let before = try #require(harness.panel(in: window))

        harness.tree.replace(Fixtures.documentWindow(id: "document"))
        #expect(harness.locate(window, at: .milliseconds(200)) == .notFound)
        harness.tree.replace(Fixtures.documentWindow(id: "document", sheets: [
            Fixtures.sheet(id: "panel-2", Fixtures.openPanelBody(.japanese)),
        ]))
        let reopened = try #require(harness.panel(in: window, at: .milliseconds(400)))

        #expect(reopened.context.id != before.context.id)
        #expect(reopened.isNewlyClassified)
    }
}
