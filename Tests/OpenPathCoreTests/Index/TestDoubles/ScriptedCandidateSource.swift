import Foundation
import os

import OpenPathCore

/// 収集の結果とタイミングをテストから操作できる CandidateSource。
///
/// - 既定では呼ばれるとすぐに `snapshot` を返す。`isGated` を true にすると、テストが `release(_:)` するまで返さない。
/// - 待っている間にキャンセルされると `CancellationError` を投げる（`honorsCancellation` が false なら投げずに待ち続ける）。
/// - 呼ばれた回数・同時に走っている数・キャンセルされた回数・実行スレッドと優先度を記録する。
///
/// `release(_:)` は待っている呼び出しがまだ無ければ次の呼び出しのために取っておくため、
/// 「呼ばれたこと」を待ってから `release` しても取りこぼさない。
///
/// 変更の検知（ChangeTrackingCandidateSource、Issue #78）: 既定では記録を返さず、周期の再構築でも毎回収集される。
/// `setTracksChanges(true)` にすると収集のたびに版（`markChanged()` で進む整数）を記録として返し、
/// `hasChanged(since:)` は記録の版が今の版と違うときだけ true を返す。
final class ScriptedCandidateSource: ChangeTrackingCandidateSource {
    private struct Gate: Sendable {
        let callID: Int
        let continuation: CheckedContinuation<CandidateSourceSnapshot?, Never>
    }

    private struct CountWaiter: Sendable {
        let id: Int
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct State: Sendable {
        var snapshot = CandidateSourceSnapshot(items: [])
        var failure: (any Error & Sendable)?
        var isGated = false
        var honorsCancellation = true
        var startedCount = 0
        var runningCount = 0
        var maxRunningCount = 0
        var cancelledCount = 0
        var ranOnMainThread = false
        var priorities: [TaskPriority] = []
        var gates: [Gate] = []
        var pendingReleases: [CandidateSourceSnapshot] = []
        var startWaiters: [CountWaiter] = []
        var nextCallID = 0
        var nextWaiterID = 0
        var tracksChanges = false
        var version = 0
        var changeCheckCount = 0
        var checkedChangesOnMainThread = false
    }

    let kind: CandidateSourceKind
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(kind: CandidateSourceKind, items: [SourceItem] = [], warnings: [CandidateSourceWarning] = []) {
        self.kind = kind
        state.withLock { $0.snapshot = CandidateSourceSnapshot(items: items, warnings: warnings) }
    }

    // MARK: - 振る舞いの設定

    /// 待たずに返すときの結果
    func setSnapshot(items: [SourceItem], warnings: [CandidateSourceWarning] = []) {
        state.withLock { $0.snapshot = CandidateSourceSnapshot(items: items, warnings: warnings) }
    }

    /// true にすると、以降の呼び出しは `release(_:)` まで返さない
    func setGated(_ isGated: Bool) {
        state.withLock { $0.isGated = isGated }
    }

    /// false にすると、待っている間にキャンセルされても返さない（キャンセルを見ないソースの再現）
    func setHonorsCancellation(_ honorsCancellation: Bool) {
        state.withLock { $0.honorsCancellation = honorsCancellation }
    }

    /// 以降の呼び出しでこのエラーを投げる（契約外のエラーの再現）
    func setFailure(_ failure: (any Error & Sendable)?) {
        state.withLock { $0.failure = failure }
    }

    /// true にすると、収集のたびに今の版を変更の記録として返す
    func setTracksChanges(_ tracksChanges: Bool) {
        state.withLock { $0.tracksChanges = tracksChanges }
    }

    /// 版を進める。以降、それより前の記録に対する `hasChanged(since:)` は true を返す
    func markChanged() {
        state.withLock { $0.version += 1 }
    }

    /// 最も古い待ちの呼び出しに `items` を返させる。待ちが無ければ次の呼び出しのために取っておく
    func release(items: [SourceItem], warnings: [CandidateSourceWarning] = []) {
        let snapshot = CandidateSourceSnapshot(items: items, warnings: warnings)
        let gate: Gate? = state.withLock { state in
            guard !state.gates.isEmpty else {
                state.pendingReleases.append(snapshot)
                return nil
            }
            return state.gates.removeFirst()
        }
        gate?.continuation.resume(returning: snapshot)
    }

    // MARK: - 記録

    var startedCount: Int {
        state.withLock { $0.startedCount }
    }

    var maxRunningCount: Int {
        state.withLock { $0.maxRunningCount }
    }

    var cancelledCount: Int {
        state.withLock { $0.cancelledCount }
    }

    var ranOnMainThread: Bool {
        state.withLock { $0.ranOnMainThread }
    }

    var priorities: [TaskPriority] {
        state.withLock { $0.priorities }
    }

    /// `hasChanged(since:)` が呼ばれた回数
    var changeCheckCount: Int {
        state.withLock { $0.changeCheckCount }
    }

    /// `hasChanged(since:)` が一度でもメインスレッドで呼ばれたか
    var checkedChangesOnMainThread: Bool {
        state.withLock { $0.checkedChangesOnMainThread }
    }

    /// 通算 `count` 回呼ばれるまで待つ。
    /// テストの時間制限でキャンセルされたときも待ちを解き、テスト実行全体が止まらないようにする。
    func waitUntilStarted(count: Int) async {
        let waiterID = state.withLock { state in
            defer { state.nextWaiterID += 1 }
            return state.nextWaiterID
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let isReached = state.withLock { state in
                    guard state.startedCount < count, !Task.isCancelled else { return true }
                    state.startWaiters.append(CountWaiter(id: waiterID, count: count, continuation: continuation))
                    return false
                }
                if isReached {
                    continuation.resume()
                }
            }
        } onCancel: {
            let waiter: CountWaiter? = state.withLock { state in
                guard let position = state.startWaiters.firstIndex(where: { $0.id == waiterID }) else { return nil }
                return state.startWaiters.remove(at: position)
            }
            waiter?.continuation.resume()
        }
    }

    // MARK: - CandidateSource

    func snapshot() async throws -> CandidateSourceSnapshot {
        let isMainThread = pthread_main_np() != 0
        let priority = Task.currentPriority
        let (callID, readyWaiters) = state.withLock { state in
            let callID = state.nextCallID
            state.nextCallID += 1
            state.startedCount += 1
            state.runningCount += 1
            state.maxRunningCount = max(state.maxRunningCount, state.runningCount)
            state.ranOnMainThread = state.ranOnMainThread || isMainThread
            state.priorities.append(priority)
            let startedCount = state.startedCount
            let ready = state.startWaiters.filter { $0.count <= startedCount }
            state.startWaiters.removeAll { $0.count <= startedCount }
            return (callID, ready)
        }
        for waiter in readyWaiters {
            waiter.continuation.resume()
        }
        defer {
            state.withLock { $0.runningCount -= 1 }
        }

        let (isGated, snapshot, failure) = state.withLock { ($0.isGated, $0.snapshot, $0.failure) }
        if let failure {
            throw failure
        }
        guard isGated else {
            try Task.checkCancellation()
            return snapshot
        }
        guard let released = await waitForRelease(callID: callID) else {
            state.withLock { $0.cancelledCount += 1 }
            throw CancellationError()
        }
        return released
    }

    // MARK: - ChangeTrackingCandidateSource

    func trackedSnapshot() async throws -> (snapshot: CandidateSourceSnapshot, marker: Int?) {
        // 本番の roots と同じく、収集の前の状態を記録する（収集中の変化を次の確認で取りこぼさないため）
        let (tracksChanges, version) = state.withLock { ($0.tracksChanges, $0.version) }
        let snapshot = try await snapshot()
        return (snapshot, tracksChanges ? version : nil)
    }

    func hasChanged(since marker: Int) async -> Bool {
        let isMainThread = pthread_main_np() != 0
        return state.withLock { state in
            state.changeCheckCount += 1
            state.checkedChangesOnMainThread = state.checkedChangesOnMainThread || isMainThread
            return state.version != marker
        }
    }

    /// `release` された結果を返す。キャンセルを尊重する設定でキャンセルされたら nil
    private func waitForRelease(callID: Int) async -> CandidateSourceSnapshot? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<CandidateSourceSnapshot?, Never>) in
                let immediate: CandidateSourceSnapshot?? = state.withLock { state in
                    if !state.pendingReleases.isEmpty {
                        return .some(state.pendingReleases.removeFirst())
                    }
                    // キャンセルフラグは onCancel より先に立つため、ロック内で確認すれば取りこぼさない
                    if state.honorsCancellation, Task.isCancelled {
                        return .some(nil)
                    }
                    state.gates.append(Gate(callID: callID, continuation: continuation))
                    return nil
                }
                if let immediate {
                    continuation.resume(returning: immediate)
                }
            }
        } onCancel: {
            let gate: Gate? = state.withLock { state in
                guard state.honorsCancellation, let position = state.gates.firstIndex(where: { $0.callID == callID }) else {
                    return nil
                }
                return state.gates.remove(at: position)
            }
            gate?.continuation.resume(returning: nil)
        }
    }
}
