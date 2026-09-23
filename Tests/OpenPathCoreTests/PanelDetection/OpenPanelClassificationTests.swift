import Testing

import OpenPathCore

@Suite("OpenPanelClassifier: 判定とファイル一覧の特定")
struct OpenPanelClassificationTests {
    private typealias Fixtures = FileListFixtures
    private typealias PanelFixtures = PanelTreeFixtures

    private static func classification(_ node: StubNode, in tree: StubPanelTree = StubPanelTree()) throws
        -> OpenPanelClassification<StubElement> {
        let candidate = tree.add(node)
        return try OpenPanelClassifier.classification(of: candidate, reader: tree)
    }

    @Test(
        "サイドバー（AXOutline）より後に現れる中身のファイル一覧を返す",
        arguments: [
            ("カラム表示", Fixtures.columnView(items: [.directory("alpha")]), "AXBrowser"),
            ("リスト表示", Fixtures.listView(items: [.directory("alpha")]), "AXOutline"),
        ]
    )
    func returnsContentFileList(label: String, fileList: StubNode, role: String) throws {
        let dialog = PanelFixtures.dialog(id: "open", Fixtures.openPanelBody(fileList: fileList))

        let result = try Self.classification(dialog)

        #expect(result.verdict == .openPanel, "\(label)")
        #expect(result.fileList == FileListElement(node: StubElement(Fixtures.fileListID), role: role), "\(label)")
    }

    @Test("ファイル一覧がなければ nil")
    func noFileList() throws {
        let alert = PanelFixtures.dialog(id: "alert", PanelFixtures.alertBody(.japanese))

        let result = try Self.classification(alert)

        #expect(result.verdict == .missingElements(hasConfirmButton: true, hasFileList: false))
        #expect(result.fileList == nil)
    }

    @Test(
        "判定と AX の読み取りは classify と同じ（ファイル一覧を返すために読み取りを増やさない）",
        arguments: PanelUILanguage.allCases
    )
    func sameVerdictAndReadsAsClassify(language: PanelUILanguage) throws {
        let bodies = [
            PanelFixtures.openPanelBody(language),
            PanelFixtures.savePanelBody(language),
            PanelFixtures.alertBody(language),
            Fixtures.openPanelBody(fileList: Fixtures.columnView(items: [.directory("alpha"), .dimmedFile("a.txt")])),
        ]
        for body in bodies {
            let classifyTree = StubPanelTree()
            let classificationTree = StubPanelTree()
            let node = PanelFixtures.dialog(id: "dialog", body)

            let verdict = try OpenPanelClassifier.classify(classifyTree.add(node), reader: classifyTree)
            let result = try OpenPanelClassifier.classification(of: classificationTree.add(node), reader: classificationTree)

            #expect(result.verdict == verdict)
            #expect(classificationTree.reads == classifyTree.reads)
        }
    }
}
