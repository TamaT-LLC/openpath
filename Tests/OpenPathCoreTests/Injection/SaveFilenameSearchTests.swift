import Testing
import OpenPathCore

@Suite("保存ファイル名欄の探索")
struct SaveFilenameSearchTests {
    private func locate(_ root: FakeAXElement, cutoff: ScanCutoff = .never) throws -> FakeAXElement? {
        try SaveFilenameSearch.locate(
            in: root, cutoff: cutoff, role: { $0.role }, subrole: { $0.subrole },
            title: { $0.title }, description: { $0.placeholder }, identifier: { $0.identifier }, children: { $0.children }
        )
    }

    private var filename: FakeAXElement { .textField("filename", placeholder: "Save As:") }
    private var save: FakeAXElement { FakeAXElement(name: "save", role: "AXButton", title: "Save") }

    @Test func findsFilenameInRemoteSheetAndSkipsGoToSheet() throws {
        let root = FakeAXElement.standardWindow([
            .textField("host-name", placeholder: "名前:"),
            .sheet("remote", [.group("view", [filename, save]), .goToSheetWindow()]),
        ])
        #expect(try locate(root)?.name == "filename")
    }

    @Test func doesNotPairSaveButtonWithAnotherSheet() throws {
        #expect(try locate(.standardWindow([.sheet("one", [filename]), .sheet("two", [save])])) == nil)
    }

    @Test func ignoresSearchAndListRenameFields() throws {
        var search = filename
        search.subrole = "AXSearchField"
        let list = FakeAXElement(name: "list", role: "AXOutline", children: [filename])
        #expect(try locate(.dialog([search, list, save])) == nil)
    }

    @Test func ambiguousNamesAreRejected() throws {
        #expect(try locate(.dialog([filename, .textField("second-name", placeholder: "名前:"), save])) == nil)
    }

    @Test func cutoffStopsBeforeReading() {
        #expect(throws: ScanCutoff.Reached.self) {
            try locate(.dialog([filename, save]), cutoff: ScanCutoff { true })
        }
    }
}
