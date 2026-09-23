import Testing

import OpenPathCore

/// AX の代わりに、張り付け・走査の呼び出しを記録し、走査結果をテストから与える。
@MainActor
final class PanelWatchEnvironmentFake: PanelWatchEnvironment {
    enum Call: Equatable {
        case attach(Int32)
        case detach
        case scan(Int32)
    }

    enum ScanBehavior {
        /// `outcome` を即座に返す
        case immediate
        /// `completeScan(with:)` が呼ばれるまで返さない
        case suspend
    }

    var scanBehavior: ScanBehavior = .immediate
    /// `.immediate` のときに返す走査結果
    var outcome: PanelScanOutcome = .found([])
    private(set) var calls: [Call] = []
    private var pendingScans: [CheckedContinuation<PanelScanOutcome, Never>] = []
    private let waiter = ConditionWaiter()

    var scanCount: Int {
        calls.filter { call in
            if case .scan = call { true } else { false }
        }.count
    }

    func attach(processID: Int32) {
        calls.append(.attach(processID))
        waiter.notify()
    }

    func detach() {
        calls.append(.detach)
        waiter.notify()
    }

    func scanPanels(processID: Int32) async -> PanelScanOutcome {
        calls.append(.scan(processID))
        switch scanBehavior {
        case .immediate:
            waiter.notify()
            return outcome
        case .suspend:
            return await withCheckedContinuation { continuation in
                pendingScans.append(continuation)
                waiter.notify()
            }
        }
    }

    func waitForScans(count: Int) async {
        await waiter.wait { self.scanCount >= count }
    }

    func waitForPendingScan() async {
        await waiter.wait { !self.pendingScans.isEmpty }
    }

    /// `.suspend` で止めている最初の走査を完了させる。
    func completeScan(with outcome: PanelScanOutcome) {
        guard !pendingScans.isEmpty else {
            Issue.record("完了させる走査がない")
            return
        }
        pendingScans.removeFirst().resume(returning: outcome)
    }
}
