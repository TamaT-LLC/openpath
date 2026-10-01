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

    /// 1ms。初出の表示の待ちの上限の直前・直後を確かめるための最小の刻み
    private static let smallestStep: Duration = .milliseconds(1)

    private let viewModel = PaletteViewModel(homeDirectory: "/Users/example")
    private let window = PaletteWindowSpy()
    private let search = ScriptedPaletteSearch()
    private let includeFiles = IncludeFilesStub()
    private let clock = TestClock()
    private let presenter: PalettePresenter

    init() {
        let includeFiles = includeFiles
        presenter = PalettePresenter(
            viewModel: viewModel,
            window: window,
            includeFiles: { includeFiles.value },
            search: search.search,
            clock: clock
        )
    }

    /// パレットを出し、最初の候補の検索に `rows` で答えて、ウィンドウが出るまで待つ。
    private func show(_ context: PanelContext, answering rows: [PaletteRow]) async {
        let callIndex = search.calls.count
        let shownCount = window.shownCount
        presenter.show(context: context)
        await search.waitForCalls(callIndex + 1)
        search.respond(to: callIndex, with: rows)
        await waitForRows(rows)
        await waitForShow(count: shownCount + 1)
    }

    private func waitForRows(_ rows: [PaletteRow]) async {
        await MainActorQueue.waitUntil { viewModel.hasReceivedRows && viewModel.rows == rows }
    }

    private func waitForShow(count: Int) async {
        await MainActorQueue.waitUntil { window.shownCount >= count }
    }

    // MARK: - 表示

    @Test("空の検索語で最初の候補を引き、候補を反映した行数でパネルの近くに表示する")
    func showsAndQueriesInitialRows() async {
        let rows = PaletteRowFixtures.rows("fern", "fern-docs")

        await show(.sample, answering: rows)

        #expect(window.calls == [.show(near: PanelContext.sample.frame, rowCount: rows.count)])
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

    @Test("別のパネルでは前回の検索語・候補・状態表示を消し、そのパネルの最初の候補で表示する")
    func newPanelResetsPalette() async {
        let rows = PaletteRowFixtures.rows("openpath")
        await show(.sample, answering: PaletteRowFixtures.rows("fern"))
        viewModel.query = "fe"
        presenter.showError("移動できませんでした")

        presenter.show(context: .another)

        #expect(viewModel.query.isEmpty)
        #expect(viewModel.rows.isEmpty)
        #expect(viewModel.emptyMessage == nil)
        #expect(viewModel.status == nil)
        await search.waitForCalls(3)
        #expect(search.calls.last?.text == "")
        search.respond(to: 2, with: rows)
        await waitForShow(count: 2)
        #expect(window.calls.last == .show(near: PanelContext.another.frame, rowCount: rows.count))
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

    // MARK: - 初出の表示（#91）

    @Test("初出の表示の待ちの上限は 100ms")
    func initialRowsWaitLimitIs100Milliseconds() {
        #expect(PalettePresenter.initialRowsWaitLimit == .milliseconds(100))
    }

    @Test("新しいパネルでは、最初の候補が届くまでウィンドウを出さず、0 件の案内も出さない")
    func newPanelWaitsForInitialRows() async {
        let rows = PaletteRowFixtures.rows("fern", "fern-docs")

        presenter.show(context: .sample)
        await search.waitForCalls(1)
        await MainActorQueue.drain()

        #expect(window.calls.isEmpty)
        #expect(viewModel.emptyMessage == nil)

        search.respond(to: 0, with: rows)
        await waitForShow(count: 1)

        #expect(window.calls == [.show(near: PanelContext.sample.frame, rowCount: rows.count)])
        #expect(viewModel.rows == rows)
    }

    @Test("最初の候補が 0 件なら、0 件の案内を出せる状態でウィンドウを出す")
    func emptyInitialRowsShowWithMessage() async {
        await show(.sample, answering: [])

        #expect(window.calls == [.show(near: PanelContext.sample.frame, rowCount: 0)])
        #expect(viewModel.emptyMessage == PaletteText.noMatches)
    }

    @Test("最初の候補が上限までに届かなければ、候補を待たずにウィンドウを出し、0 件の案内は出さない")
    func showsWithoutRowsAfterWaitLimit() async {
        let rows = PaletteRowFixtures.rows("fern", "fern-docs")
        presenter.show(context: .sample)
        await search.waitForCalls(1)

        clock.advance(by: PalettePresenter.initialRowsWaitLimit - Self.smallestStep)
        await MainActorQueue.drain()
        #expect(window.calls.isEmpty)

        clock.advance(by: Self.smallestStep)
        await waitForShow(count: 1)
        #expect(window.calls == [.show(near: PanelContext.sample.frame, rowCount: 0)])
        #expect(viewModel.emptyMessage == nil)

        // 後から届いた候補は表示中のパレットに反映し、ウィンドウを出し直さない
        search.respond(to: 0, with: rows)
        await waitForRows(rows)
        #expect(window.rowCount == rows.count)
        #expect(window.shownCount == 1)
    }

    @Test("候補を引けなかった（取り消し以外のエラー）場合も、上限を過ぎたらウィンドウを出す")
    func showsAfterWaitLimitWhenSearchFails() async {
        struct SearchFailure: Error {}
        presenter.show(context: .sample)
        await search.waitForCalls(1)
        search.fail(0, with: SearchFailure())
        await MainActorQueue.drain()
        #expect(window.calls.isEmpty)

        clock.advance(by: PalettePresenter.initialRowsWaitLimit)
        await waitForShow(count: 1)

        #expect(window.calls == [.show(near: PanelContext.sample.frame, rowCount: 0)])
        #expect(viewModel.emptyMessage == nil)
    }

    @Test("最初の候補を待っている間に閉じたら、候補が届いても上限を過ぎてもウィンドウを出さない")
    func hideWhileWaitingCancelsShow() async {
        presenter.show(context: .sample)
        await search.waitForCalls(1)

        presenter.hide()
        search.respond(to: 0, with: PaletteRowFixtures.rows("fern"))
        clock.advance(by: PalettePresenter.initialRowsWaitLimit)
        await MainActorQueue.drain()

        #expect(window.calls == [.hide])
    }

    @Test("最初の候補を待っている間に別のパネルを出したら、そのパネルの候補で出す")
    func anotherPanelWhileWaitingShowsLatestPanel() async {
        let rows = PaletteRowFixtures.rows("openpath")
        presenter.show(context: .sample)
        await search.waitForCalls(1)

        presenter.show(context: .another)
        await search.waitForCalls(2)
        search.respond(to: 0, with: PaletteRowFixtures.rows("fern", "fern-docs"))
        search.respond(to: 1, with: rows)
        await waitForShow(count: 1)

        #expect(window.calls == [.show(near: PanelContext.another.frame, rowCount: rows.count)])
        #expect(viewModel.rows == rows)
    }

    @Test("最初の候補を待っている間に別のパネルを出したら、待ちの上限はそのパネルを出したときから数える")
    func waitLimitRestartsForAnotherPanel() async {
        let halfLimit = PalettePresenter.initialRowsWaitLimit / 2
        presenter.show(context: .sample)
        await search.waitForCalls(1)
        clock.advance(by: halfLimit)

        presenter.show(context: .another)
        await search.waitForCalls(2)
        clock.advance(by: halfLimit)
        await MainActorQueue.drain()
        #expect(window.calls.isEmpty)

        clock.advance(by: halfLimit)
        await waitForShow(count: 1)
        #expect(window.calls == [.show(near: PanelContext.another.frame, rowCount: 0)])
    }

    @Test("待ちの上限に達した直後に別のパネルを出したら、前のパネルの待ちで新しいパネルを出さない")
    func expiredWaitDoesNotRevealNextPanel() async {
        presenter.show(context: .sample)
        await search.waitForCalls(1)
        await MainActorQueue.drain()

        // 前のパネルの待ちが期限に達したが、その続きが MainActor で走る前に別のパネルを出す
        clock.advance(by: PalettePresenter.initialRowsWaitLimit)
        presenter.show(context: .another)
        await search.waitForCalls(2)
        await MainActorQueue.drain()

        #expect(window.calls.isEmpty)
    }

    @Test("最初の候補を待っている間にパネルが動いたら、置き直さずに新しい位置で出す")
    func movedPanelWhileWaitingShowsAtNewFrame() async {
        let rows = PaletteRowFixtures.rows("fern")
        let moved = PanelContext(id: PanelContext.sample.id, isDirectoriesOnly: false, frame: PanelContext.another.frame)
        presenter.show(context: .sample)
        await search.waitForCalls(1)

        presenter.update(context: moved)
        search.respond(to: 0, with: rows)
        await waitForShow(count: 1)

        #expect(window.calls == [.show(near: PanelContext.another.frame, rowCount: rows.count)])
    }

    @Test("最初の候補を待っている間のエラー表示では、まだ出していないパレットのキー入力を奪わない")
    func errorWhileWaitingDoesNotReclaimKey() async {
        presenter.show(context: .sample)
        await search.waitForCalls(1)

        presenter.showError("移動できませんでした")

        #expect(window.calls.isEmpty)
        #expect(viewModel.status == .error("移動できませんでした"))
    }

    @Test("候補を受け取り済みのパネルの再表示では、候補を待たずにすぐ出す")
    func samePanelWithReceivedRowsShowsImmediately() async {
        let rows = PaletteRowFixtures.rows("fern", "fern-docs")
        await show(.sample, answering: rows)
        presenter.hide()

        presenter.show(context: .sample)

        #expect(window.calls.last == .show(near: PanelContext.sample.frame, rowCount: rows.count))
        #expect(viewModel.rows == rows)
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

    @Test("表示中のパネルの位置が変わっていたら、候補は引き直さずにパレットを置き直す")
    func movedPanelRepositionsPalette() async {
        await show(.sample, answering: [])
        let moved = PanelContext(id: PanelContext.sample.id, isDirectoriesOnly: false, frame: PanelContext.another.frame)

        presenter.update(context: moved)
        await MainActorQueue.drain()

        #expect(window.calls.last == .reposition(near: PanelContext.another.frame))
        #expect(search.calls.count == 1)
    }

    @Test("表示中でないパネルの更新や、閉じた後の更新では何もしない")
    func irrelevantUpdatesAreIgnored() async {
        await show(.sample, answering: [])
        let callsAfterShow = window.calls

        presenter.update(context: .another)
        presenter.update(context: .sample)
        presenter.hide()
        presenter.update(context: PanelContext(id: PanelContext.sample.id, isDirectoriesOnly: true, frame: .zero))
        await MainActorQueue.drain()

        #expect(search.calls.count == 1)
        #expect(window.calls == callsAfterShow + [.hide])
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

    // MARK: - 候補の差し替え（履歴のクリア。Issue #92）

    @Test("構築中に候補が差し替わったら、表示中の候補を引き直し、消えた候補を選んでいたら先頭を選ぶ")
    func candidatesChangeDuringBuildRefreshesRows() async {
        let rows = PaletteRowFixtures.rows("history-only", "fern")
        presenter.candidateRebuildingDidChange(true)
        await show(.sample, answering: rows)

        presenter.candidatesDidChange()
        await search.waitForCalls(2)
        let refreshed = PaletteRowFixtures.rows("fern")
        search.respond(to: 1, with: refreshed)
        await waitForRows(refreshed)

        #expect(search.calls.map(\.text) == ["", ""])
        #expect(viewModel.selectedRow == refreshed[0])
        // 構築中の表示は全件の構築を終えるまで残す
        #expect(viewModel.isBuildingCandidates)
    }

    @Test("候補が差し替わっても検索語を変えず、選択していた候補が残っていれば選択を保つ")
    func candidatesChangeKeepsQueryAndSelection() async {
        await show(.sample, answering: [])
        viewModel.query = "fe"
        await search.waitForCalls(2)
        let rows = PaletteRowFixtures.rows("history-only", "fern", "fern-docs")
        search.respond(to: 1, with: rows)
        await waitForRows(rows)
        viewModel.moveSelection(by: 2)

        presenter.candidatesDidChange()
        await search.waitForCalls(3)
        let refreshed = PaletteRowFixtures.rows("fern", "fern-docs")
        search.respond(to: 2, with: refreshed)
        await waitForRows(refreshed)

        #expect(search.calls.map(\.text) == ["", "fe", "fe"])
        #expect(viewModel.query == "fe")
        #expect(viewModel.selectedRow == rows[2])
    }

    @Test("閉じている間に候補が差し替わっても候補を引かない")
    func candidatesChangeWhileHiddenDoesNotQuery() async {
        await show(.sample, answering: PaletteRowFixtures.rows("fern"))
        presenter.hide()

        presenter.candidatesDidChange()
        await MainActorQueue.drain()

        #expect(search.calls.count == 1)
    }
}
