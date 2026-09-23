import Testing

import OpenPathCore

@Suite("OpenPanelLocator: 選択モードを推定し直す予定の公開")
struct OpenPanelSelectionModeProvisionalTests {
    private typealias Fixtures = FileListFixtures

    private static let folderOnlyItems: [FileListItem] = [
        .directory("alpha"), .directory("beta"), .dimmedFile("delta.md"),
    ]

    private static func dialog(_ fileList: StubNode) -> StubNode {
        PanelTreeFixtures.dialog(id: "open", Fixtures.openPanelBody(fileList: fileList))
    }

    @Test("行を読めずに推定し直す予定の間は isSelectionModeProvisional を立て、推定し直して行を読めたら下ろす")
    func provisionalUntilRowsAreRead() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.dialog(Fixtures.columnView(items: [])))
        let first = try #require(harness.panel(in: window))

        harness.tree.replace(Fixtures.columnView(items: Self.folderOnlyItems))
        let settled = try #require(harness.panel(in: window, at: .milliseconds(250)))

        #expect(first.context.isSelectionModeProvisional)
        #expect(settled.context.isSelectionModeProvisional == false)
        #expect(settled.context.isDirectoriesOnly)
    }

    @Test("推定し直す回数を使い切ったら、推定できないまま isSelectionModeProvisional を下ろす")
    func settlesAfterRetriesAreExhausted() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.dialog(Fixtures.columnView(items: [])))
        // 推定する時刻（最初の判定と 4 回の推定し直し。OpenPanelSelectionModeTests.retrySchedule と同じ）
        let estimationElapsedMilliseconds = [0, 250, 750, 1_750, 3_750]

        let contexts = estimationElapsedMilliseconds.compactMap { elapsed in
            harness.panel(in: window, at: .milliseconds(elapsed))?.context
        }

        #expect(contexts.map(\.isSelectionModeProvisional) == [true, true, true, true, false])
        #expect(contexts.last?.isDirectoriesOnly == false)
    }

    @Test("行を読めたパネルは最初から isSelectionModeProvisional を立てない")
    func notProvisionalWhenRowsAreRead() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.dialog(Fixtures.columnView(items: Self.folderOnlyItems)))

        #expect(try #require(harness.panel(in: window)).context.isSelectionModeProvisional == false)
    }
}
