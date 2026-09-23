import OpenPathCore

/// PanelWatchEngine とテストダブル一式を組み立て、通知されたイベントを記録する。
@MainActor
final class PanelWatchEngineHarness {
    static let pollingInterval: Duration = .milliseconds(200)
    /// 1ms。ポーリング間隔の直前・直後を確かめるための最小の刻み
    static let smallestStep: Duration = .milliseconds(1)
    /// ポーリングが止まっていることを確かめるために進める時間（周期 5 回分）
    static let severalIntervals: Duration = pollingInterval * 5
    /// MainActor に積まれた後続ジョブ（走査・ポーリングのタスク）を先に走らせるための譲り回数
    private static let drainIterations = 20

    let clock = TestClock()
    let environment = PanelWatchEnvironmentFake()
    let disabledApps: DisabledAppsStub
    let engine: PanelWatchEngine
    /// 記録した後にイベントを渡す先。AppCoordinator との連携を確かめるときに使う。
    var forwardEvent: (@MainActor (CoordinatorEvent) -> Void)?
    private(set) var events: [CoordinatorEvent] = []
    private let eventWaiter = ConditionWaiter()

    init() {
        let disabledApps = DisabledAppsStub()
        self.disabledApps = disabledApps
        engine = PanelWatchEngine(
            ownProcessID: PanelWatchFixtures.ownProcessID,
            environment: environment,
            isAppDisabled: { disabledApps.contains($0) },
            pollingInterval: Self.pollingInterval,
            clock: clock
        )
        engine.onEvent = { [weak self] event in
            self?.record(event)
        }
    }

    func waitForEvents(count: Int) async {
        await eventWaiter.wait { self.events.count >= count }
    }

    /// 「何も起きないこと」を確かめる前や時計を進める前に、保留中の MainActor ジョブを処理させる。
    func drainMainActor() async {
        for _ in 0..<Self.drainIterations {
            await Task.yield()
        }
    }

    /// AppCoordinator と、#27 で想定する形（onEvent → handle、onStateChange → coordinatorStateDidChange）でつなぐ。
    func connect(to coordinatorHarness: CoordinatorHarness) {
        let coordinator = coordinatorHarness.coordinator
        let recordState = coordinator.onStateChange
        coordinator.onStateChange = { [engine] state in
            recordState?(state)
            engine.coordinatorStateDidChange(state)
        }
        forwardEvent = { event in
            coordinator.handle(event)
        }
    }

    private func record(_ event: CoordinatorEvent) {
        events.append(event)
        eventWaiter.notify()
        forwardEvent?(event)
    }
}
