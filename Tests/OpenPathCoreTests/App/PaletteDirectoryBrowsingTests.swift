import Foundation
import Testing
import OpenPathCore

@MainActor
@Suite("PalettePresenter: Tab でフォルダを掘り下げる", .timeLimit(.minutes(1)))
struct PaletteDirectoryBrowsingTests {
    private let tree: FileTreeFixture
    private let viewModel = PaletteViewModel()
    private let window = PaletteWindowSpy()

    init() throws { tree = try FileTreeFixture() }

    private func waitForNames(_ names: [String]) async {
        await MainActorQueue.waitUntil {
            viewModel.directoryMessage != PaletteText.loadingDirectory && viewModel.rows.map(\.name) == names
        }
    }

    @Test("depth=2 の索引から Tab を繰り返して深い階層へ進める。範囲外の似たパスは混ざらない")
    func endToEndExpansion() async throws {
        try tree.makeDirectories("a/b/c/d", "a/b-other/c")
        try tree.makeFiles("a/b/c/file.txt")
        let index = CandidateIndex(history: { [] })
        let snapshot = try RootDirectoryScanner(options: .init(depth: 2)).scan(root: tree.root)
        await index.replace(source: .root(tree.root), with: snapshot.items)
        let presenter = PalettePresenter(
            viewModel: viewModel, window: window, includeFiles: { true },
            search: PaletteCandidateSearch.make(index: index)
        )
        presenter.show(context: .sample)
        await MainActorQueue.waitUntil { viewModel.hasReceivedRows }
        viewModel.query = tree.path("a/b")
        await MainActorQueue.waitUntil { viewModel.selectedRow?.path == tree.path("a/b") }
        _ = viewModel.perform(.expandSelection)
        #expect(viewModel.expandedDirectory == tree.path("a/b"))
        #expect(viewModel.rows.isEmpty)
        #expect(viewModel.emptyMessage == PaletteText.loadingDirectory)
        await waitForNames(["c"])
        _ = viewModel.perform(.expandSelection)
        await waitForNames(["d", "file.txt"])
        #expect(viewModel.query == tree.path("a/b/c/"))
        presenter.update(context: .init(id: PanelContext.sample.id, isDirectoriesOnly: true, frame: PanelContext.sample.frame))
        await waitForNames(["d"])
        #expect(viewModel.perform(.confirm(openImmediately: false)) == .confirm(path: tree.path("a/b/c/d"), openImmediately: false))
        presenter.hide()
    }

    @Test("直接入力は自動列挙せず、候補を Tab で選んだときだけ列挙する")
    func directPathRequiresTab() async throws {
        try tree.makeDirectories(".hidden/child")
        let index = CandidateIndex(history: { [] })
        let presenter = PalettePresenter(
            viewModel: viewModel, window: window, includeFiles: { false },
            search: PaletteCandidateSearch.make(index: index)
        )
        presenter.show(context: .sample)
        await MainActorQueue.waitUntil { viewModel.hasReceivedRows }
        viewModel.query = tree.path(".hidden")
        await MainActorQueue.waitUntil { viewModel.selectedRow?.path == tree.path(".hidden") }
        #expect(viewModel.expandedDirectory == nil)
        _ = viewModel.perform(.expandSelection)
        await waitForNames(["child"])
        #expect(viewModel.expandedDirectory == tree.path(".hidden"))
        presenter.hide()
    }

    @Test("読み込み中でも Esc で閉じられ、遅れた結果は表示せず、再表示では読み直す")
    func hideCancelsAndReshowReloads() async {
        let loader = ScriptedDirectoryLoad()
        let initial = PaletteRowFixtures.rows("folder")
        let presenter = PalettePresenter(
            viewModel: viewModel, window: window, includeFiles: { false },
            search: { _, _, _ in initial }, loadDirectory: loader.load
        )
        presenter.show(context: .sample)
        await MainActorQueue.waitUntil { viewModel.hasReceivedRows }
        _ = viewModel.perform(.expandSelection)
        await loader.waitForCalls(1)
        #expect(viewModel.perform(.dismiss) == .dismiss)
        presenter.hide()
        #expect(viewModel.rows.isEmpty)
        loader.respond(0, message: "stale")
        await MainActorQueue.drain()
        #expect(viewModel.directoryMessage == nil)
        presenter.show(context: .sample)
        await loader.waitForCalls(2)
        loader.respond(1)
        await MainActorQueue.waitUntil { viewModel.emptyMessage == PaletteText.emptyDirectory }
        #expect(loader.paths == [initial[0].path, initial[0].path])
        presenter.hide()
    }

    @Test("パスの接頭辞を編集すると通常検索へ戻り、列挙中の結果を捨てる")
    func leavingScopeCancelsListing() async {
        let loader = ScriptedDirectoryLoad()
        let initial = PaletteRowFixtures.rows("folder")
        let presenter = PalettePresenter(
            viewModel: viewModel, window: window, includeFiles: { false },
            search: { _, _, _ in initial }, loadDirectory: loader.load
        )
        presenter.show(context: .sample)
        await MainActorQueue.waitUntil { viewModel.hasReceivedRows }
        _ = viewModel.perform(.expandSelection)
        await loader.waitForCalls(1)
        viewModel.query = "new query"
        #expect(viewModel.expandedDirectory == nil)
        await MainActorQueue.waitUntil { viewModel.rows == initial }
        loader.respond(0, message: "stale")
        await MainActorQueue.drain()
        #expect(viewModel.rows == initial)
        #expect(viewModel.directoryMessage == nil)
        presenter.hide()
    }

    @Test("別のパネルではフォルダ範囲を忘れ、通常の初回候補を待つ")
    func anotherPanelClearsScope() async {
        let loader = ScriptedDirectoryLoad()
        let search = ScriptedPaletteSearch()
        let presenter = PalettePresenter(
            viewModel: viewModel, window: window, includeFiles: { false },
            search: search.search, loadDirectory: loader.load
        )
        presenter.show(context: .sample)
        await search.waitForCalls(1)
        search.respond(to: 0, with: PaletteRowFixtures.rows("folder"))
        await MainActorQueue.waitUntil { viewModel.hasReceivedRows }
        _ = viewModel.perform(.expandSelection)
        await loader.waitForCalls(1)
        presenter.show(context: .another)
        #expect(viewModel.expandedDirectory == nil)
        #expect(!viewModel.hasReceivedRows)
        #expect(viewModel.directoryMessage == nil)
        await search.waitForCalls(2)
        loader.respond(0, message: "stale")
        search.respond(to: 1, with: [])
        await MainActorQueue.waitUntil { viewModel.hasReceivedRows }
        #expect(viewModel.emptyMessage == PaletteText.noMatches)
        presenter.hide()
    }

    @Test("ファイル候補の Tab は列挙せず通常のパス入力にする")
    func filesDoNotExpand() async {
        let file = PaletteRow(name: "file.txt", path: "/example/file.txt", lastUsed: nil, isDirectory: false)
        viewModel.replaceRows([file])
        _ = viewModel.perform(.expandSelection)
        #expect(viewModel.expandedDirectory == nil)
        #expect(viewModel.query == file.path)
    }

    @Test("閉じた後も選択パスは覚え、再列挙後に選択を復元する")
    func reshowRestoresSelectionWithoutKeepingRows() async throws {
        try tree.makeDirectories("a", "b")
        let rootRow = PaletteRow(name: "root", path: tree.root, lastUsed: nil)
        let presenter = PalettePresenter(
            viewModel: viewModel, window: window, includeFiles: { false }, search: { _, _, _ in [rootRow] }
        )
        presenter.show(context: .sample)
        await MainActorQueue.waitUntil { viewModel.hasReceivedRows }
        _ = viewModel.perform(.expandSelection)
        await waitForNames(["a", "b"])
        viewModel.select(at: 1)
        presenter.hide()
        #expect(viewModel.rows.isEmpty)
        presenter.show(context: .sample)
        await waitForNames(["a", "b"])
        #expect(viewModel.selectedRow?.name == "b")
        presenter.hide()
    }
}
