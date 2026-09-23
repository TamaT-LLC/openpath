import CoreGraphics

import OpenPathCore

/// AppCoordinator とテストダブル一式を組み立て、非同期の状態遷移を待ち合わせる。
@MainActor
final class CoordinatorHarness {
    /// MainActor に積まれた後続ジョブ（再開済みの注入タスク等）を先に走らせるための譲り回数。
    /// main キューは FIFO のため 1 回で足りるが、ジョブが数段連鎖しても足りるよう余裕を持たせる。
    private static let drainIterations = 20

    let palette = PaletteSpy()
    let history = HistorySpy()
    let clock = TestClock()
    let injector: InjectorFake
    let settings: SettingsStub
    let coordinator: AppCoordinator
    private(set) var observedStates: [CoordinatorState] = []
    private let stateWaiter = ConditionWaiter()

    init(injectorBehavior: InjectorFake.Behavior = .succeed, isAutoConfirmEnabled: Bool = false) {
        let injector = InjectorFake(behavior: injectorBehavior)
        let settings = SettingsStub(isAutoConfirmEnabled: isAutoConfirmEnabled)
        self.injector = injector
        self.settings = settings
        coordinator = AppCoordinator(
            palette: palette,
            injector: injector,
            history: history,
            isAutoConfirmEnabled: { settings.isAutoConfirmEnabled },
            clock: clock
        )
        coordinator.onStateChange = { [weak self] state in
            self?.didObserve(state)
        }
    }

    /// 期待する状態になるまで待つ。既にその状態なら即座に戻る。
    func waitForState(_ expected: CoordinatorState) async {
        await stateWaiter.wait { self.coordinator.state == expected }
    }

    /// 「何も起きないこと」を確かめる前に、保留中の MainActor ジョブを処理させる。
    func drainMainActor() async {
        for _ in 0..<Self.drainIterations {
            await Task.yield()
        }
    }

    /// パネルを検知させ、パレット表示中（PanelShown）にする。
    func showPanel(_ context: PanelContext = .sample) {
        coordinator.handle(.panelAppeared(context))
    }

    private func didObserve(_ state: CoordinatorState) {
        observedStates.append(state)
        stateWaiter.notify()
    }
}

extension PanelContext {
    static let sample = PanelContext(
        id: PanelContext.ID(rawValue: "panel-1"),
        isDirectoriesOnly: false,
        frame: CGRect(x: 100, y: 100, width: 800, height: 600)
    )

    static let another = PanelContext(
        id: PanelContext.ID(rawValue: "panel-2"),
        isDirectoriesOnly: true,
        frame: CGRect(x: 300, y: 200, width: 700, height: 500)
    )
}
