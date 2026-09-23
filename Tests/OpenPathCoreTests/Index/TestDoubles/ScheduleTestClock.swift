import os

/// 再構築の周期を実時間を待たずに検証するため、テストから手動で進める Clock。
///
/// Coordinator の TestClock と同じく `advance(by:)` で期限に達した sleep を再開させる。加えて、
/// sleep が登録されるまで待つ `waitUntilSleeping(count:)` を持つ。再構築の完了後に周期の待ちが始まる前に
/// 時刻を進めてしまうと、待ちの期限が進めた後の時刻から数えられてしまうため。
final class ScheduleTestClock: Clock {
    struct Instant: InstantProtocol {
        let offset: Swift.Duration

        func advanced(by duration: Swift.Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Swift.Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper: Sendable {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct CountWaiter: Sendable {
        let id: Int
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct State: Sendable {
        var currentInstant = Instant(offset: .zero)
        var sleepers: [Sleeper] = []
        var sleepWaiters: [CountWaiter] = []
        var nextSleeperID = 0
        var nextWaiterID = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var now: Instant {
        state.withLock { $0.currentInstant }
    }

    var minimumResolution: Swift.Duration {
        .zero
    }

    /// 期限を待っている sleep の数
    var sleeperCount: Int {
        state.withLock { $0.sleepers.count }
    }

    func sleep(until deadline: Instant, tolerance: Swift.Duration?) async throws {
        let sleeperID = state.withLock { state in
            defer { state.nextSleeperID += 1 }
            return state.nextSleeperID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let (immediateResult, readyWaiters) = state.withLock { state -> (Result<Void, any Error>?, [CountWaiter]) in
                    // キャンセルフラグは onCancel より先に立つため、ロック内で確認すれば取りこぼさない
                    if Task.isCancelled {
                        return (.failure(CancellationError()), [])
                    }
                    if deadline <= state.currentInstant {
                        return (.success(()), [])
                    }
                    state.sleepers.append(Sleeper(id: sleeperID, deadline: deadline, continuation: continuation))
                    let sleeperCount = state.sleepers.count
                    let ready = state.sleepWaiters.filter { $0.count <= sleeperCount }
                    state.sleepWaiters.removeAll { $0.count <= sleeperCount }
                    return (nil, ready)
                }
                for waiter in readyWaiters {
                    waiter.continuation.resume()
                }
                if let immediateResult {
                    continuation.resume(with: immediateResult)
                }
            }
        } onCancel: {
            let cancelled: Sleeper? = state.withLock { state in
                guard let position = state.sleepers.firstIndex(where: { $0.id == sleeperID }) else { return nil }
                return state.sleepers.remove(at: position)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    /// 時刻を進め、期限に達した sleep を再開させる。
    func advance(by duration: Swift.Duration) {
        let dueSleepers: [Sleeper] = state.withLock { state in
            state.currentInstant = state.currentInstant.advanced(by: duration)
            let now = state.currentInstant
            let due = state.sleepers.filter { $0.deadline <= now }
            state.sleepers.removeAll { $0.deadline <= now }
            return due
        }
        for sleeper in dueSleepers {
            sleeper.continuation.resume()
        }
    }

    /// 期限を待っている sleep が `count` 個以上になるまで待つ。
    /// テストの時間制限でキャンセルされたときも待ちを解き、テスト実行全体が止まらないようにする。
    func waitUntilSleeping(count: Int) async {
        let waiterID = state.withLock { state in
            defer { state.nextWaiterID += 1 }
            return state.nextWaiterID
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let isReached = state.withLock { state in
                    guard state.sleepers.count < count, !Task.isCancelled else { return true }
                    state.sleepWaiters.append(CountWaiter(id: waiterID, count: count, continuation: continuation))
                    return false
                }
                if isReached {
                    continuation.resume()
                }
            }
        } onCancel: {
            let waiter: CountWaiter? = state.withLock { state in
                guard let position = state.sleepWaiters.firstIndex(where: { $0.id == waiterID }) else { return nil }
                return state.sleepWaiters.remove(at: position)
            }
            waiter?.continuation.resume()
        }
    }
}
