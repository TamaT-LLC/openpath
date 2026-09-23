import CoreGraphics
import Testing

import OpenPathCore

@MainActor
@Suite("PalettePresenter", .timeLimit(.minutes(1)))
struct PalettePresenterTests {
    /// 設定 include_files の差し替え用。設定ファイルの変更を再現するため可変にしている。
    @MainActor
    final class IncludeFilesStub {
        var value = false
    }

    private let viewModel = PaletteViewModel(homeDirectory: "/Users/example")
    private let window = PaletteWindowSpy()
    private let search = ScriptedPaletteSearch()
    private let includeFiles = IncludeFilesStub()
    private let presenter: PalettePresenter

    init() {
        let includeFiles = includeFiles
        presenter = PalettePresenter(
            viewModel: viewModel,
            window: window,
            includeFiles: { includeFiles.value },
            search: search.search
        )
    }

    /// パレットを出し、最初の候補の検索に `rows` で答える。
    private func show(_ context: PanelContext, answering rows: [PaletteRow]) async {
        let callIndex = search.calls.count
        presenter.show(context: context)
        await search.waitForCalls(callIndex + 1)
        search.respond(to: callIndex, with: rows)
        await waitForRows(rows)
    }

    private func waitForRows(_ rows: [PaletteRow]) async {
        await MainActorQueue.waitUntil { viewModel.rows == rows }
    }

    // MARK: - 表示

    @Test("パネルの近くに表示し、空の検索語で最初の候補を引いて反映する")
    func showsAndQueriesInitialRows() async {
        let rows = PaletteRowFixtures.rows("fern", "fern-docs")

        await show(.sample, answering: rows)

        #expect(window.calls == [.show(near: PanelContext.sample.frame, rowCount: 0)])
        #expect(search.calls == [.init(text: "", directoriesOnly: true, limit: PaletteQuerySession.resultLimit)])
        #expect(viewModel.rows == rows)
        #expect(viewModel.selectedIndex == 0)
        #expect(window.rowCount == rows.count)
    }

    @Test(
        "候補をディレクトリに絞るかはパネルの推定と、候補を引く時点の include_files で決める",
        arguments: [
            (context: PanelContext.sample, includeFiles: true, expected: false),
            (context: PanelContext.sample, includeFiles: false, expected: true),
            (context: PanelContext.another, includeFiles: true, expected: true),
        ]
    )
    func directoriesOnlyFollowsPanelAndSetting(context: PanelContext, includeFiles value: Bool, expected: Bool) async {
        includeFiles.value = value

        presenter.show(context: context)
        await search.waitForCalls(1)

        #expect(search.calls.map(\.directoriesOnly) == [expected])
    }

    @Test("別のパネルでは前回の検索語・候補・状態表示を消す")
    func newPanelResetsPalette() async {
        await show(.sample, answering: PaletteRowFixtures.rows("fern"))
        viewModel.query = "fe"
        presenter.showError("移動できませんでした")

        presenter.show(context: .another)

        #expect(viewModel.query.isEmpty)
        #expect(viewModel.rows.isEmpty)
        #expect(viewModel.status == nil)
        #expect(window.calls.last == .show(near: PanelContext.another.frame, rowCount: 0))
        await search.waitForCalls(3)
        #expect(search.calls.last?.text == "")
    }

    @Test("同じパネルを再表示したときは検索語と選択を保ち、状態表示を消して候補を引き直す")
    func samePanelKeepsQueryAndSelection() async {
        let rows = PaletteRowFixtures.rows("fern", "fern-docs")
        await show(.sample, answering: PaletteRowFixtures.rows("fern"))
        viewModel.query = "fe"
        await search.waitForCalls(2)
        search.respond(to: 1, with: rows)
        await waitForRows(rows)
        viewModel.moveSelection(by: 1)
        presenter.showError("移動できませんでした")
        presenter.hide()

        presenter.show(context: .sample)
        await search.waitForCalls(3)
        let refreshed = PaletteRowFixtures.rows("openpath", "fern", "fern-docs")
        search.respond(to: 2, with: refreshed)
        await waitForRows(refreshed)

        #expect(viewModel.query == "fe")
        #expect(viewModel.status == nil)
        #expect(search.calls.last?.text == "fe")
        #expect(viewModel.selectedRow == rows[1])
        #expect(window.calls.last == .show(near: PanelContext.sample.frame, rowCount: rows.count))
    }

    // MARK: - パネルの情報の更新

    @Test("表示中のパネルがフォルダのみと分かったら、ディレクトリに絞って選択を保ったまま引き直す")
    func updatedSelectionModeRequeries() async {
        includeFiles.value = true
        let rows = PaletteRowFixtures.rows("fern", "fern-docs")
        await show(.sample, answering: rows)
        viewModel.moveSelection(by: 1)
        let updated = PanelContext(id: PanelContext.sample.id, isDirectoriesOnly: true, frame: PanelContext.sample.frame)

        presenter.update(context: updated)
        await search.waitForCalls(2)
        let refreshed = PaletteRowFixtures.rows("openpath", "fern", "fern-docs")
        search.respond(to: 1, with: refreshed)
        await waitForRows(refreshed)

        #expect(search.calls.map(\.directoriesOnly) == [false, true])
        #expect(viewModel.selectedRow == rows[1])
    }

    @Test("フォルダのみかどうかが変わらない更新や、表示中でないパネルの更新では引き直さない")
    func irrelevantUpdatesAreIgnored() async {
        await show(.sample, answering: [])
        let moved = PanelContext(id: PanelContext.sample.id, isDirectoriesOnly: false, frame: PanelContext.another.frame)

        presenter.update(context: moved)
        presenter.update(context: .another)
        presenter.hide()
        presenter.update(context: PanelContext(id: PanelContext.sample.id, isDirectoriesOnly: true, frame: .zero))
        await MainActorQueue.drain()

        #expect(search.calls.count == 1)
    }

    // MARK: - 検索語の変更

    @Test("表示中は検索語が変わるたびに候補を引き直す")
    func queryChangeRequestsRows() async {
        let rows = PaletteRowFixtures.rows("fern")
        await show(.sample, answering: PaletteRowFixtures.rows("fern", "openpath"))

        viewModel.query = "fe"
        await search.waitForCalls(2)
        search.respond(to: 1, with: rows)
        await waitForRows(rows)

        #expect(search.calls.map(\.text) == ["", "fe"])
        #expect(window.rowCount == rows.count)
    }

    @Test("表示していない間は検索語が変わっても候補を引かない")
    func queryChangeWhileHiddenIsIgnored() async {
        viewModel.query = "fe"
        await show(.sample, answering: [])
        presenter.hide()

        viewModel.query = "fer"
        await MainActorQueue.drain()

        #expect(search.calls.map(\.text) == [""])
    }

    // MARK: - 閉じる

    @Test("閉じると実行中の検索を取り消し、結果が届いても反映しない")
    func hideCancelsPendingQuery() async {
        presenter.show(context: .sample)
        await search.waitForCalls(1)

        presenter.hide()
        await search.waitForCancellation(of: 0)
        search.respond(to: 0, with: PaletteRowFixtures.rows("fern"))
        await MainActorQueue.drain()

        #expect(window.calls.last == .hide)
        #expect(viewModel.rows.isEmpty)
    }

    // MARK: - 注入中・失敗

    @Test("ロックと状態表示をビューモデルへ伝える")
    func forwardsLockAndStatus() {
        presenter.setLocked(true)
        presenter.showStatus(PaletteMessage.injecting)

        #expect(viewModel.isLocked)
        #expect(viewModel.status == .info(PaletteMessage.injecting))
    }

    @Test("注入のキー操作の前に、表示したままキー入力をパネルへ返す")
    func releasesKeyForInjection() async {
        await show(.sample, answering: [])

        presenter.releaseKeyForInjection()

        #expect(window.calls.last == .releaseKey)
    }

    @Test("表示中にエラーを出すと、再試行できるようパレットにキー入力を戻す")
    func errorReclaimsKey() async {
        await show(.sample, answering: [])
        presenter.releaseKeyForInjection()

        presenter.showError("移動できませんでした")

        #expect(viewModel.status == .error("移動できませんでした"))
        #expect(window.calls.suffix(2) == [.releaseKey, .reclaimKey])
    }

    @Test("閉じている間のエラー表示ではキー入力を奪わない")
    func errorWhileHiddenDoesNotReclaimKey() {
        presenter.showError("移動できませんでした")

        #expect(!window.calls.contains(.reclaimKey))
    }

    // MARK: - 候補の再構築

    @Test("最初の構築中はフッターに構築中を出し、終えたら表示中の候補を選択を保って引き直す")
    func firstBuildShowsStatusAndRefreshes() async {
        let rows = PaletteRowFixtures.rows("fern", "fern-docs")
        await show(.sample, answering: rows)
        viewModel.moveSelection(by: 1)

        presenter.candidateRebuildingDidChange(true)
        let isBuildingWhileRebuilding = viewModel.isBuildingCandidates
        presenter.candidateRebuildingDidChange(false)
        await search.waitForCalls(2)
        let refreshed = PaletteRowFixtures.rows("openpath", "fern", "fern-docs")
        search.respond(to: 1, with: refreshed)
        await waitForRows(refreshed)

        #expect(isBuildingWhileRebuilding)
        #expect(viewModel.isBuildingCandidates == false)
        #expect(search.calls.last?.text == "")
        #expect(viewModel.selectedRow == rows[1])
    }

    @Test("2 回目以降の構築ではフッターに構築中を出さない")
    func laterBuildsDoNotShowStatus() {
        presenter.candidateRebuildingDidChange(true)
        presenter.candidateRebuildingDidChange(false)

        presenter.candidateRebuildingDidChange(true)

        #expect(viewModel.isBuildingCandidates == false)
    }

    @Test("閉じている間に構築を終えても候補を引かない")
    func buildFinishedWhileHiddenDoesNotQuery() async {
        presenter.candidateRebuildingDidChange(true)
        presenter.candidateRebuildingDidChange(false)
        await MainActorQueue.drain()

        #expect(search.calls.isEmpty)
    }
}
