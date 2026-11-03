import Testing
import OpenPathCore

@Suite("保存パネルの識別と候補制限")
struct SavePanelDetectionTests {
    @Test(arguments: PanelUILanguage.allCases)
    func remoteSavePanel(language: PanelUILanguage) throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(PanelTreeFixtures.documentWindow(id: "document", sheets: [
            PanelTreeFixtures.remoteSheet(id: "save", PanelTreeFixtures.savePanelBody(language)),
        ]))
        let panel = try #require(harness.panel(in: window))
        #expect(panel.context.kind == .save)
        #expect(panel.context.isDirectoriesOnly)
        #expect(!panel.context.isSelectionModeProvisional)
        #expect(harness.panel(in: window)?.context.id == panel.context.id)
        harness.locator.forget(panel.element)
        #expect(harness.panel(in: window)?.context.id != panel.context.id)
    }

    @Test("保存識別子は、名前欄を読めずボタンが Open でも開くパネルにならない")
    func saveIdentifierWins() throws {
        let tree = StubPanelTree()
        let candidate = tree.add(PanelTreeFixtures.nonModalPanelWindow(
            id: "save", identifier: "save-panel", PanelTreeFixtures.openPanelBody(.english)
        ))
        #expect(try OpenPanelClassifier.classify(candidate, reader: tree) == .savePanel)
    }

    @Test("コンパクトな保存パネルは save-panel 識別子と保存ボタンで認識する")
    func compactSavePanel() throws {
        let tree = StubPanelTree()
        let candidate = tree.add(PanelTreeFixtures.nonModalPanelWindow(id: "save", identifier: "save-panel", [
            PanelTreeFixtures.textField(description: "Save As:"), PanelTreeFixtures.button("Save"),
        ]))
        #expect(try OpenPanelClassifier.classify(candidate, reader: tree) == .savePanel)
    }

    @Test("保存ボタンと名前欄だけの通常のアラートは受け入れない")
    func renameAlertIsNotSavePanel() throws {
        let tree = StubPanelTree()
        let candidate = tree.add(PanelTreeFixtures.dialog(id: "alert", [
            PanelTreeFixtures.textField(description: "名前:"), PanelTreeFixtures.button("保存"),
        ]))
        #expect(try OpenPanelClassifier.classify(candidate, reader: tree) == .missingElements(hasConfirmButton: true, hasFileList: false))
    }
}
