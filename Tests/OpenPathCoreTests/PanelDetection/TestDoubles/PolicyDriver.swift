import Testing

import OpenPathCore

/// PanelWatchPolicy に入力を与え、依頼された走査を覚えておく。
/// 走査の id は実装の都合で振られるため、テストでは `Step` に読み替えて比較する。
struct PolicyDriver {
    /// 副作用を、走査の id を除いて比較するための表現。
    enum Step: Equatable {
        case attach(Int32)
        case detach
        case startPolling
        case stopPolling
        case scan(Int32)
        case send(CoordinatorEvent)
    }

    let disabledApps: DisabledAppsStub
    private(set) var policy: PanelWatchPolicy
    /// 依頼されたまま完了していない走査（依頼順）
    private(set) var pendingScans: [PanelScanRequest] = []

    init(disabledApps: DisabledAppsStub = DisabledAppsStub()) {
        self.disabledApps = disabledApps
        policy = PanelWatchPolicy(
            ownProcessID: PanelWatchFixtures.ownProcessID,
            isAppDisabled: { disabledApps.contains($0) }
        )
    }

    @discardableResult
    mutating func send(_ input: PanelWatchInput) -> [Step] {
        let effects = policy.handle(input)
        for case .scan(let request) in effects {
            pendingScans.append(request)
        }
        return effects.map(Self.step(for:))
    }

    /// 最後に依頼された走査を完了させる。
    @discardableResult
    mutating func completeLatestScan(_ outcome: PanelScanOutcome) -> [Step] {
        guard let request = pendingScans.popLast() else {
            Issue.record("完了させる走査が依頼されていない")
            return []
        }
        return send(.scanCompleted(PanelScanResult(requestID: request.id, outcome: outcome)))
    }

    /// 最初に依頼された走査を完了させる。張り替え前の古い走査の結果が遅れて届く状況を再現する。
    @discardableResult
    mutating func completeOldestScan(_ outcome: PanelScanOutcome) -> [Step] {
        guard !pendingScans.isEmpty else {
            Issue.record("完了させる走査が依頼されていない")
            return []
        }
        let request = pendingScans.removeFirst()
        return send(.scanCompleted(PanelScanResult(requestID: request.id, outcome: outcome)))
    }

    /// 開始して最前面のアプリに張り付き、最初の走査を完了させた状態にする。
    mutating func startWatching(_ application: ActiveApplication = .finder, initialPanels: [PanelContext] = []) {
        send(.start(frontmost: application))
        completeLatestScan(.found(initialPanels))
    }

    private static func step(for effect: PanelWatchEffect) -> Step {
        switch effect {
        case .attach(let processID): .attach(processID)
        case .detach: .detach
        case .startPolling: .startPolling
        case .stopPolling: .stopPolling
        case .scan(let request): .scan(request.processID)
        case .send(let event): .send(event)
        }
    }
}
