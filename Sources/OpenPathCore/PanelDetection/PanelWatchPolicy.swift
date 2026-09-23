/// PanelWatcher の状態管理（DSN-001 §2.1）。AX・NSWorkspace から切り離した純粋な状態機械。
///
/// 入力（`PanelWatchInput`）を受けて状態を進め、実行すべき副作用（`PanelWatchEffect`）を返す。決めるのは次の 3 つ:
/// - どのアプリに張り付くか: 最前面のアプリ。ただし自プロセスは無視し（観測中のアプリを外さない）、
///   `disabled_apps` のアプリには張り付かない
/// - 補助ポーリングの開始・停止: 張り付いていて、AppCoordinator が Idle の間だけポーリングする。
///   ただし AXObserver を張れなかったアプリでは、パネルの消滅を検知するため Idle 以外でもポーリングする。
///   追跡中のパネルの選択モードを推定し直す予定の間（`PanelContext.isSelectionModeProvisional`）も、
///   推定し直す走査の機会を作るため Idle 以外でもポーリングする（推定し直しは最大 4 回・約 4 秒で終わる）
/// - AppCoordinator へ送るイベント: 走査で見つけたパネルを追跡し、出現・消滅を 1 回ずつ送る。
///   Idle に戻った後も同じパネルが開いたままなら、もう一度だけ `panelAppeared` を送る
///   （注入タイムアウトで Idle に戻ると AppCoordinator はパネルを見失い、ホットキーも受け付けないため）。
///   通知済みのパネルのフォルダのみかどうか（推定し直し）か位置が変わっていたら、`panelContextChanged` を送る。
///   位置の変化は、走査したとき（AX 通知・ポーリング）に分かった分だけ送る（移動の通知は観測していない）
public struct PanelWatchPolicy {
    /// `start` 済みで `stop` されていないか。
    public private(set) var isStarted = false
    /// 張り付いているアプリのプロセス ID。
    public private(set) var attachedProcessID: Int32?
    /// 補助ポーリング中か。
    public private(set) var isPolling = false
    /// `panelAppeared` を送り、まだ `panelGone` を送っていないパネル。
    public private(set) var trackedPanel: PanelContext?

    private let ownProcessID: Int32
    private let isAppDisabled: (String) -> Bool
    /// 最後に最前面になった自プロセス以外のアプリ。disabled_apps の変更時に判定し直すため、張り付いていなくても覚えておく
    private var frontApplication: ActiveApplication?
    private var coordinatorState: CoordinatorState = .idle
    /// 張り付いているアプリから AX 通知を受け取れるか。AXObserver を張れなかったら false にし、張り替えたら戻す
    private var canReceiveAXNotifications = true
    /// AppCoordinator が最後に Idle になってから、追跡中のパネルを通知したか
    private var isTrackedPanelAnnouncedSinceIdle = false
    private var nextScanID = 0
    /// 結果待ちの走査。走査は同時に 1 つだけ行い、これと一致しない結果は古いものとして捨てる
    private var inFlightScanID: Int?
    /// 走査中に AX 通知が届き、完了後にもう一度走査する必要があるか
    private var isRescanPending = false

    /// - Parameters:
    ///   - ownProcessID: openpath 自身のプロセス ID。
    ///   - isAppDisabled: bundle id が設定 `disabled_apps` に含まれるか。設定の変更を反映するため判定のたびに呼ぶ。
    public init(ownProcessID: Int32, isAppDisabled: @escaping (String) -> Bool) {
        self.ownProcessID = ownProcessID
        self.isAppDisabled = isAppDisabled
    }

    /// 入力を反映し、実行すべき副作用を実行順に返す。
    public mutating func handle(_ input: PanelWatchInput) -> [PanelWatchEffect] {
        var effects: [PanelWatchEffect] = []
        switch input {
        case .start(let frontmost):
            start(frontmost: frontmost, effects: &effects)
        case .stop:
            stop(effects: &effects)
        case .applicationActivated(let application):
            applicationActivated(application, effects: &effects)
        case .applicationTerminated(let processID):
            applicationTerminated(processID: processID, effects: &effects)
        case .disabledAppsChanged:
            reconcile(effects: &effects)
        case .coordinatorStateChanged(let state):
            coordinatorStateChanged(state, effects: &effects)
        case .axNotificationReceived(let processID):
            guard processID == attachedProcessID else { break }
            requestScan(effects: &effects)
        case .axObservationFailed(let processID):
            axObservationFailed(processID: processID, effects: &effects)
        case .pollTick:
            // 走査が長引いている間に周期ごとの走査を積み上げると、AX のキューが空かなくなるため捨てる
            guard isPolling, inFlightScanID == nil else { break }
            requestScan(effects: &effects)
        case .scanCompleted(let result):
            scanCompleted(result, effects: &effects)
        }
        return effects
    }

    // MARK: - 入力ごとの処理

    private mutating func start(frontmost: ActiveApplication?, effects: inout [PanelWatchEffect]) {
        guard !isStarted else { return }
        isStarted = true
        if let frontmost {
            // 自プロセスが最前面なら、アプリ切り替えと同じく直前に観測していたアプリを使う
            if frontmost.processID != ownProcessID {
                frontApplication = frontmost
            }
        } else {
            // 停止中はアプリの切り替えを追っていないため、停止前のアプリが今も最前面とは限らない
            frontApplication = nil
        }
        reconcile(effects: &effects)
    }

    private mutating func stop(effects: inout [PanelWatchEffect]) {
        guard isStarted else { return }
        isStarted = false
        reconcile(effects: &effects)
    }

    private mutating func applicationActivated(_ application: ActiveApplication, effects: inout [PanelWatchEffect]) {
        // パレットは openpath をアクティブにしないが、メニューバー等で openpath が前面に来ても観測中のパネルを見失わないようにする
        guard application.processID != ownProcessID else { return }
        frontApplication = application
        reconcile(effects: &effects)
    }

    private mutating func applicationTerminated(processID: Int32, effects: inout [PanelWatchEffect]) {
        guard frontApplication?.processID == processID else { return }
        frontApplication = nil
        reconcile(effects: &effects)
    }

    private mutating func coordinatorStateChanged(_ state: CoordinatorState, effects: inout [PanelWatchEffect]) {
        let isReturningToIdle = coordinatorState != .idle && state == .idle
        coordinatorState = state
        updatePolling(effects: &effects)
        guard isReturningToIdle else { return }
        isTrackedPanelAnnouncedSinceIdle = false
        requestScan(effects: &effects)
    }

    private mutating func axObservationFailed(processID: Int32, effects: inout [PanelWatchEffect]) {
        guard processID == attachedProcessID, canReceiveAXNotifications else { return }
        canReceiveAXNotifications = false
        let wasPolling = isPolling
        updatePolling(effects: &effects)
        // PanelShown 中に分かった場合、止めていた間にパネルが閉じられているかもしれないため、すぐに確かめる
        if !wasPolling, isPolling {
            requestScan(effects: &effects)
        }
    }

    private mutating func scanCompleted(_ result: PanelScanResult, effects: inout [PanelWatchEffect]) {
        guard result.requestID == inFlightScanID else { return }
        inFlightScanID = nil
        if case .found(let panels) = result.outcome {
            applyScannedPanels(panels, effects: &effects)
        }
        guard isRescanPending else { return }
        isRescanPending = false
        requestScan(effects: &effects)
    }

    // MARK: - 張り付けとポーリング

    /// 張り付けるべきアプリとポーリングの要否を現在の状態から決め直す。
    private mutating func reconcile(effects: inout [PanelWatchEffect]) {
        updateAttachment(effects: &effects)
        updatePolling(effects: &effects)
    }

    private mutating func updateAttachment(effects: inout [PanelWatchEffect]) {
        let desiredProcessID = processIDToAttach()
        guard desiredProcessID != attachedProcessID else { return }

        // 追跡中のパネルは張り替え前のアプリのもの。観測できなくなるので、パレットを閉じられるよう消えたことにする
        if trackedPanel != nil {
            trackedPanel = nil
            effects.append(.send(.panelGone))
        }
        inFlightScanID = nil
        isRescanPending = false
        canReceiveAXNotifications = true
        attachedProcessID = desiredProcessID

        if let desiredProcessID {
            effects.append(.attach(processID: desiredProcessID))
            // 切り替え先のアプリで既に開いているパネルを、次の周期を待たずに拾う
            requestScan(effects: &effects)
        } else {
            effects.append(.detach)
        }
    }

    private func processIDToAttach() -> Int32? {
        guard isStarted, let frontApplication else { return nil }
        if let bundleIdentifier = frontApplication.bundleIdentifier, isAppDisabled(bundleIdentifier) {
            return nil
        }
        return frontApplication.processID
    }

    private mutating func updatePolling(effects: inout [PanelWatchEffect]) {
        // AX 通知を受け取れないアプリでは、PanelShown 中もポーリングしないとパネルの消滅に気づけない。
        // 選択モードを推定し直す予定のパネルも、PanelShown 中に走査しないと推定し直す機会が無い
        let needsScansWhileBusy = !canReceiveAXNotifications || trackedPanel?.isSelectionModeProvisional == true
        let shouldPoll = attachedProcessID != nil && (coordinatorState == .idle || needsScansWhileBusy)
        guard shouldPoll != isPolling else { return }
        isPolling = shouldPoll
        effects.append(shouldPoll ? .startPolling : .stopPolling)
    }

    // MARK: - 走査

    /// 走査を依頼する。走査中なら完了後にもう一度だけ走査するよう予約し、依頼を重ねない。
    private mutating func requestScan(effects: inout [PanelWatchEffect]) {
        guard let attachedProcessID else { return }
        guard inFlightScanID == nil else {
            isRescanPending = true
            return
        }
        let request = PanelScanRequest(id: nextScanID, processID: attachedProcessID)
        nextScanID += 1
        inFlightScanID = request.id
        effects.append(.scan(request))
    }

    private mutating func applyScannedPanels(_ panels: [PanelContext], effects: inout [PanelWatchEffect]) {
        // 追跡中のパネルの選択モードの推定し直しの予定が変われば、ポーリングの要否も変わる
        defer { updatePolling(effects: &effects) }
        if let tracked = trackedPanel {
            if let current = panels.first(where: { $0.id == tracked.id }) {
                trackedPanel = current
                let hasChanged = current.isDirectoriesOnly != tracked.isDirectoriesOnly || current.frame != tracked.frame
                if !reannounceIfNeeded(current, effects: &effects), hasChanged {
                    effects.append(.send(.panelContextChanged(current)))
                }
                return
            }
            trackedPanel = nil
            effects.append(.send(.panelGone))
        }

        guard let newPanel = panels.first else { return }
        trackedPanel = newPanel
        isTrackedPanelAnnouncedSinceIdle = true
        effects.append(.send(.panelAppeared(newPanel)))
    }

    /// 追跡中のパネルは、AppCoordinator が Idle に戻ってからまだ通知していない場合に限り通知し直す。
    /// PanelShown 中の重複通知や、Idle のままの再通知（ポーリングのたびにパレットが出る）を防ぐ。
    /// - Returns: 通知し直したか。通知し直した場合は最新の `PanelContext` を渡しているため、更新の通知は要らない。
    private mutating func reannounceIfNeeded(_ panel: PanelContext, effects: inout [PanelWatchEffect]) -> Bool {
        guard coordinatorState == .idle, !isTrackedPanelAnnouncedSinceIdle else { return false }
        isTrackedPanelAnnouncedSinceIdle = true
        effects.append(.send(.panelAppeared(panel)))
        return true
    }
}
