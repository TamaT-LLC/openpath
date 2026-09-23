/// `PanelWatchPolicy` を動かし、決まった副作用（張り付け・走査・補助ポーリング・イベント送出）を実行する。
///
/// AX から切り離してあるため、ポーリングの周期や AppCoordinator との連携を Core のテストで確かめられる。
/// OpenPathMac の PanelWatcher が NSWorkspace と AXObserver の出来事をここへ渡す。
@MainActor
public final class PanelWatchEngine {
    /// 補助ポーリングの間隔（DSN-001 §2.1）。
    public static let defaultPollingInterval: Duration = .milliseconds(200)

    /// パネルの出現（`panelAppeared`）・消滅（`panelGone`）を知らせる。AppCoordinator.handle へつなぐ想定。
    /// この中から同期的に `coordinatorStateDidChange(_:)` 等が呼ばれても、現在の入力を処理し終えてから順に処理する。
    public var onEvent: (@MainActor (CoordinatorEvent) -> Void)?

    /// `start` 済みで `stop` されていないか。
    public var isRunning: Bool {
        policy.isStarted
    }

    private var policy: PanelWatchPolicy
    /// 所有者（PanelWatcher）が environment と engine の両方を持つため、循環参照にならないよう弱参照にする
    private weak var environment: (any PanelWatchEnvironment)?
    private let pollingInterval: Duration
    private let clock: any Clock<Duration>
    private var pollingTask: Task<Void, Never>?
    /// onEvent 等から入れ子で届いた入力。副作用の途中で状態機械を進めないよう、現在の入力を処理し終えてから処理する
    private var pendingInputs: [PanelWatchInput] = []
    private var isProcessingInput = false

    /// - Parameters:
    ///   - ownProcessID: openpath 自身のプロセス ID。
    ///   - environment: AX の窓口。弱参照で持つため、呼び出し側で保持すること。
    ///   - isAppDisabled: bundle id が設定 `disabled_apps` に含まれるか。MainActor で、判定のたびに呼ぶ。
    ///   - pollingInterval: 補助ポーリングの間隔。
    ///   - clock: ポーリングの待機に使う。テストでは手動で進める Clock を渡す。
    public init(
        ownProcessID: Int32,
        environment: any PanelWatchEnvironment,
        isAppDisabled: @escaping (String) -> Bool,
        pollingInterval: Duration = defaultPollingInterval,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        policy = PanelWatchPolicy(ownProcessID: ownProcessID, isAppDisabled: isAppDisabled)
        self.environment = environment
        self.pollingInterval = pollingInterval
        self.clock = clock
    }

    deinit {
        pollingTask?.cancel()
    }

    // MARK: - 入力

    /// 監視を始める。開始済みなら何もしない。
    /// - Parameter frontmost: その時点の最前面アプリ。
    public func start(frontmost: ActiveApplication?) {
        process(.start(frontmost: frontmost))
    }

    /// 監視をやめる。パネルを追跡中なら `panelGone` を送る。
    public func stop() {
        process(.stop)
    }

    /// 最前面のアプリが切り替わったときに呼ぶ（`NSWorkspace.didActivateApplicationNotification`）。
    public func applicationDidActivate(_ application: ActiveApplication) {
        process(.applicationActivated(application))
    }

    /// アプリが終了したときに呼ぶ（`NSWorkspace.didTerminateApplicationNotification`）。
    public func applicationDidTerminate(processID: Int32) {
        process(.applicationTerminated(processID: processID))
    }

    /// 設定 `disabled_apps` が変わったときに呼ぶ。最前面のアプリを判定し直す。
    public func disabledAppsDidChange() {
        process(.disabledAppsChanged)
    }

    /// AppCoordinator の状態が変わったときに呼ぶ（`AppCoordinator.onStateChange` からつなぐ）。
    /// PanelShown / Injecting の間は補助ポーリングを止め、Idle に戻ると再開する。
    public func coordinatorStateDidChange(_ state: CoordinatorState) {
        process(.coordinatorStateChanged(state))
    }

    /// 観測中のアプリから AX 通知が届いたときに呼ぶ。
    public func axNotificationDidArrive(processID: Int32) {
        process(.axNotificationReceived(processID: processID))
    }

    /// processID のアプリに AXObserver を張れなかったときに呼ぶ。
    /// 通知が届かないため、AppCoordinator が PanelShown / Injecting の間もポーリングを続け、パネルの消滅を検知する。
    public func axObservationDidFail(processID: Int32) {
        process(.axObservationFailed(processID: processID))
    }

    // MARK: - 副作用の実行

    private func process(_ input: PanelWatchInput) {
        pendingInputs.append(input)
        guard !isProcessingInput else { return }
        isProcessingInput = true
        defer { isProcessingInput = false }

        while !pendingInputs.isEmpty {
            let next = pendingInputs.removeFirst()
            for effect in policy.handle(next) {
                perform(effect)
            }
        }
    }

    private func perform(_ effect: PanelWatchEffect) {
        switch effect {
        case .attach(let processID):
            environment?.attach(processID: processID)
        case .detach:
            environment?.detach()
        case .startPolling:
            startPolling()
        case .stopPolling:
            stopPolling()
        case .scan(let request):
            scan(request)
        case .send(let event):
            onEvent?(event)
        }
    }

    private func scan(_ request: PanelScanRequest) {
        guard let environment else { return }
        Task { [weak self] in
            let outcome = await environment.scanPanels(processID: request.processID)
            self?.process(.scanCompleted(PanelScanResult(requestID: request.id, outcome: outcome)))
        }
    }

    private func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Self.makePollingTask(on: clock, interval: pollingInterval) { [weak self] in
            self?.process(.pollTick)
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// 周期の待機を Task.sleep ではなく Clock で行い、テストで時間を進められるようにする。
    /// `any Clock` のままでは Instant を扱えないため、具体的な型として受け取る。
    private static func makePollingTask<C: Clock<Duration>>(
        on clock: C,
        interval: Duration,
        onTick: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                do {
                    try await clock.sleep(until: clock.now.advanced(by: interval), tolerance: nil)
                } catch {
                    return
                }
                onTick()
            }
        }
    }
}
