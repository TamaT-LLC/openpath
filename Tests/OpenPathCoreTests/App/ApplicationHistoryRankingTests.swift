import Foundation
import Testing
import OpenPathCore

@Suite("アプリ別の候補順位", .timeLimit(.minutes(1)))
struct ApplicationHistoryRankingTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)
    private static let editor = "org.example.editor"
    private static let browser = "org.example.browser"

    private static func history(_ paths: [String]) -> [HistoryEntry] {
        [
            HistoryEntry(path: paths[0], count: 5, lastUsed: now, applications: [editor: .init(count: 5, lastUsed: now)]),
            HistoryEntry(path: paths[1], count: 6, lastUsed: now, applications: [browser: .init(count: 6, lastUsed: now)]),
        ]
    }

    @Test("同じ検索語でも呼び出し元で順位が変わり、未知のアプリは全体へ戻る", arguments: ["", "project"])
    func ranksByCallingApp(query: String) async throws {
        let paths = ["/example/project-a", "/example/project-b"]
        let history = Self.history(paths)
        let index = CandidateIndex(fileExistence: RecordingFileExistenceChecker(), now: { Self.now }, history: { history })
        await index.replace(source: .history, with: paths.map { SourceItem(path: $0, isDirectory: true) })
        let editor = try await index.query(query, directoriesOnly: true, limit: 50, applicationBundleID: Self.editor)
        let browser = try await index.query(query, directoriesOnly: true, limit: 50, applicationBundleID: Self.browser)
        let unknown = try await index.query(query, directoriesOnly: true, limit: 50, applicationBundleID: "org.example.unknown")
        #expect(editor.map(\.candidate.path) == paths)
        #expect(browser.map(\.candidate.path) == paths.reversed())
        #expect(unknown.map(\.candidate.path) == paths.reversed())
        #expect(try await index.query("no-match", directoriesOnly: true, limit: 50, applicationBundleID: Self.editor).isEmpty)
    }

    @Test("Tab で読み込む直下の候補にも同じアプリ別順位を適用する")
    func directorySearchUsesAppHistory() async throws {
        let tree = try FileTreeFixture()
        try tree.makeDirectories("project-a", "project-b")
        let paths = [tree.path("project-a"), tree.path("project-b")]
        let snapshot = try await DirectorySnapshot.load(directory: tree.root, ignoredNames: [])
        let editor = try await snapshot.search("project", directoriesOnly: true, limit: 50, history: Self.history(paths), now: Self.now, applicationBundleID: Self.editor)
        let browser = try await snapshot.search("project", directoriesOnly: true, limit: 50, history: Self.history(paths), now: Self.now, applicationBundleID: Self.browser)
        #expect(editor.rows.map(\.path) == paths)
        #expect(browser.rows.map(\.path) == paths.reversed())
    }

    @Test("XPC 要素の情報を持っていても走査対象アプリを呼び出し元にし、座標変換で失わない")
    func attributesXPCPanelToCallingApp() {
        let xpc = PanelContext.sample.withCallingApplication("com.apple.appkit.xpc.openAndSavePanelService")
        #expect(xpc.callingApplicationBundleID == nil)
        let caller = xpc.withCallingApplication(Self.editor)
        #expect(caller.withFrame(.zero).callingApplicationBundleID == Self.editor)
        #expect(caller.id == xpc.id)
    }

    @Test("注入開始時のパネルの呼び出し元を履歴記録まで引き継ぐ")
    @MainActor
    func coordinatorRecordsCaller() async {
        let harness = CoordinatorHarness(injectorBehavior: .suspend(respondsToCancellation: false), isAutoConfirmEnabled: true)
        let context = PanelContext.sample.withCallingApplication(Self.editor)
        harness.showPanel(context)
        harness.coordinator.handle(.confirm(path: "/example/project", openImmediately: true))
        await harness.injector.waitUntilCalled()
        // 注入中のアプリ切替でパネルを見失っても、保存先の帰属は開始時のアプリから変わらない。
        harness.coordinator.handle(.panelContextChanged(context.withCallingApplication(Self.browser)))
        harness.coordinator.handle(.panelGone)
        harness.injector.resume(with: .success(()))
        await harness.drainMainActor()
        #expect(harness.history.recordedPaths == ["/example/project"])
        #expect(harness.history.recordedApplications == [Self.editor])
    }
}

@MainActor
@Suite("パレットの呼び出し元履歴", .timeLimit(.minutes(1)))
struct PaletteApplicationHistoryTests {
    @Test("同じパネルの呼び出し元更新を通常検索と Tab の直下検索へ反映する")
    func presenterForwardsCallerToBothSearches() async throws {
        let tree = try FileTreeFixture()
        try tree.makeDirectories("project-a", "project-b")
        let now = Date()
        let editor = "org.example.editor"
        let browser = "org.example.browser"
        let paths = [tree.path("project-a"), tree.path("project-b")]
        let history = [
            HistoryEntry(path: paths[0], count: 5, lastUsed: now, applications: [editor: .init(count: 5, lastUsed: now)]),
            HistoryEntry(path: paths[1], count: 6, lastUsed: now, applications: [browser: .init(count: 6, lastUsed: now)]),
        ]
        let index = CandidateIndex(history: { history })
        await index.replace(source: .root(tree.root), with: paths.map { SourceItem(path: $0, isDirectory: true) })
        let model = PaletteViewModel()
        let window = PaletteWindowSpy()
        let presenter = PalettePresenter(
            viewModel: model, window: window, includeFiles: { false },
            search: PaletteCandidateSearch.make(index: index), contextualSearch: PaletteCandidateSearch.makeContextual(index: index),
            history: { history }
        )
        let editorContext = PanelContext.sample.withCallingApplication(editor)
        let browserContext = PanelContext.sample.withCallingApplication(browser)
        presenter.show(context: editorContext)
        await MainActorQueue.waitUntil { model.hasReceivedRows }
        #expect(model.rows.first?.path == paths[0])
        presenter.update(context: browserContext)
        await MainActorQueue.waitUntil { model.rows.first?.path == paths[1] }

        model.query = tree.root
        await MainActorQueue.waitUntil { model.selectedRow?.path == tree.root }
        _ = model.perform(.expandSelection)
        await MainActorQueue.waitUntil { model.directoryMessage == nil && model.rows.first?.path == paths[1] }
        presenter.update(context: editorContext)
        await MainActorQueue.waitUntil { model.rows.first?.path == paths[0] }
        #expect(model.expandedDirectory == tree.root)
        presenter.hide()
    }
}
