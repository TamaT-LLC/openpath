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
    private let presenter: PalettePresenter

    init() {
        let window = window
        let recorder = recorder
        presenter = PalettePresenter(
            viewModel: PaletteViewModel(homeDirectory: "/Users/example"),
            window: window,
            includeFiles: { false },
            search: ScriptedPaletteSearch().search,
            didShow: { context in
                recorder.record(Notification(panelID: context.id, lastWindowCall: window.calls.last))
            }
        )
    }

    @Test("ウィンドウを出した直後に、表示したパネルを知らせる")
    func notifiesAfterShowingWindow() {
        presenter.show(context: .sample)

        #expect(recorder.notifications == [
            Notification(panelID: PanelContext.sample.id, lastWindowCall: .show(near: PanelContext.sample.frame, rowCount: 0)),
        ])
    }

    @Test("表示のたびに 1 回知らせる（同じパネルの再表示・別のパネルでも）")
    func notifiesEveryShow() {
        presenter.show(context: .sample)
        presenter.hide()
        presenter.show(context: .sample)
        presenter.hide()
        presenter.show(context: .another)

        #expect(recorder.notifications.map(\.panelID) == [
            PanelContext.sample.id, PanelContext.sample.id, PanelContext.another.id,
        ])
    }

    @Test("位置の合わせ直し・閉じる・キー入力の受け渡しでは知らせない")
    func doesNotNotifyOtherOperations() {
        presenter.show(context: .sample)
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
