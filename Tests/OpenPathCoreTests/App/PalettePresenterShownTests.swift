import CoreGraphics
import Testing

import OpenPathCore

/// パレットを表示したことの知らせ（検知レイテンシの計測に使う `palette shown` のログ）。
@MainActor
@Suite("PalettePresenter: 表示の知らせ", .timeLimit(.minutes(1)))
struct PalettePresenterShownTests {
    /// 知らせを受けたパネルと、その時点でウィンドウに最後に行った操作。
    struct Notification: Equatable {
        let panelID: PanelContext.ID
        let lastWindowCall: PaletteWindowSpy.Call?
    }

    @MainActor
    final class ShownRecorder {
        private(set) var notifications: [Notification] = []

        func record(_ notification: Notification) {
            notifications.append(notification)
        }
    }

    private let window = PaletteWindowSpy()
    private let recorder = ShownRecorder()
    private let search = ScriptedPaletteSearch()
    private let clock = TestClock()
    private let presenter: PalettePresenter

    init() {
        let window = window
        let recorder = recorder
        presenter = PalettePresenter(
            viewModel: PaletteViewModel(homeDirectory: "/Users/example"),
            window: window,
            includeFiles: { false },
            search: search.search,
            clock: clock,
            didShow: { context in
                recorder.record(Notification(panelID: context.id, lastWindowCall: window.calls.last))
            }
        )
    }

    /// パレットを出し、最初の候補の検索に `rows` で答えて、知らせが届くまで待つ。
    private func show(_ context: PanelContext, answering rows: [PaletteRow]) async {
        let callIndex = search.calls.count
        let notificationCount = recorder.notifications.count
        presenter.show(context: context)
        await search.waitForCalls(callIndex + 1)
        search.respond(to: callIndex, with: rows)
        await MainActorQueue.waitUntil { recorder.notifications.count > notificationCount }
    }

    @Test("新しいパネルでは、最初の候補を反映してウィンドウを出した直後に知らせる（検知レイテンシの終点）")
    func notifiesAfterShowingWindowWithInitialRows() async {
        let rows = PaletteRowFixtures.rows("fern", "fern-docs")
        presenter.show(context: .sample)
        await search.waitForCalls(1)
        await MainActorQueue.drain()
        // 候補を待っている間はウィンドウを出していないため知らせない
        #expect(recorder.notifications.isEmpty)

        search.respond(to: 0, with: rows)
        await MainActorQueue.waitUntil { !recorder.notifications.isEmpty }

        #expect(recorder.notifications == [
            Notification(
                panelID: PanelContext.sample.id,
                lastWindowCall: .show(near: PanelContext.sample.frame, rowCount: rows.count)
            ),
        ])
    }

    @Test("最初の候補を待ちきれずにウィンドウを出したときも、出した直後に知らせる")
    func notifiesWhenShownAfterWaitLimit() async {
        presenter.show(context: .sample)
        await search.waitForCalls(1)

        clock.advance(by: PalettePresenter.initialRowsWaitLimit)
        await MainActorQueue.waitUntil { !recorder.notifications.isEmpty }

        #expect(recorder.notifications == [
            Notification(panelID: PanelContext.sample.id, lastWindowCall: .show(near: PanelContext.sample.frame, rowCount: 0)),
        ])
    }

    @Test("最初の候補を待っている間に閉じたら、ウィンドウを出さないため知らせない")
    func doesNotNotifyWhenHiddenWhileWaiting() async {
        presenter.show(context: .sample)
        await search.waitForCalls(1)

        presenter.hide()
        search.respond(to: 0, with: PaletteRowFixtures.rows("fern"))
        clock.advance(by: PalettePresenter.initialRowsWaitLimit)
        await MainActorQueue.drain()

        #expect(recorder.notifications.isEmpty)
    }

    @Test("表示のたびに 1 回知らせる（同じパネルの再表示・別のパネルでも）")
    func notifiesEveryShow() async {
        await show(.sample, answering: PaletteRowFixtures.rows("fern"))
        presenter.hide()
        // 同じパネルの再表示は候補を待たずにすぐ出す（引き直しの検索が届いてから閉じ、次の表示の検索と取り違えない）
        presenter.show(context: .sample)
        await search.waitForCalls(2)
        presenter.hide()
        await show(.another, answering: PaletteRowFixtures.rows("openpath"))

        #expect(recorder.notifications.map(\.panelID) == [
            PanelContext.sample.id, PanelContext.sample.id, PanelContext.another.id,
        ])
    }

    @Test("位置の合わせ直し・閉じる・キー入力の受け渡しでは知らせない")
    func doesNotNotifyOtherOperations() async {
        await show(.sample, answering: PaletteRowFixtures.rows("fern"))
        let moved = PanelContext(id: PanelContext.sample.id, isDirectoriesOnly: false, frame: PanelContext.another.frame)

        presenter.update(context: moved)
        presenter.releaseKeyForInjection()
        presenter.showError("移動できませんでした")
        presenter.hide()

        #expect(recorder.notifications.count == 1)
    }

    @Test("ログは panel detected と同じ書式でパネル ID を含み、パスを含まない")
    func logMessageMatchesPanelDetectedFormat() {
        let message = PalettePresenter.shownLogMessage(for: PanelContext.sample)

        #expect(message == "palette shown (id: \(PanelContext.sample.id.rawValue))")
        #expect(!message.contains("/"))
    }
}
