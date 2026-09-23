import Foundation

/// 実時間を待たずにタイムアウトを検証するため、テストから手動で進める Clock。
/// `@unchecked Sendable` の根拠: 可変状態はすべて `lock` で保護している。
final class TestClock: Clock, @unchecked Sendable {
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

    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var currentInstant = Instant(offset: .zero)
    private var sleepers: [Sleeper] = []
    private var nextSleeperID = 0

    var now: Instant {
        lock.withLock { currentInstant }
    }

    var minimumResolution: Swift.Duration {
        .zero
    }

    func sleep(until deadline: Instant, tolerance: Swift.Duration?) async throws {
        let sleeperID = lock.withLock {
            defer { nextSleeperID += 1 }
            return nextSleeperID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let immediateResult: Result<Void, any Error>? = lock.withLock {
                    // キャンセルフラグは onCancel より先に立つため、ロック内で確認すれば取りこぼさない
                    if Task.isCancelled {
                        return .failure(CancellationError())
                    }
                    if deadline <= currentInstant {
                        return .success(())
                    }
                    sleepers.append(Sleeper(id: sleeperID, deadline: deadline, continuation: continuation))
                    return nil
                }
                if let immediateResult {
                    continuation.resume(with: immediateResult)
                }
            }
        } onCancel: {
            let cancelled: Sleeper? = lock.withLock {
                guard let index = sleepers.firstIndex(where: { $0.id == sleeperID }) else { return nil }
                return sleepers.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    /// 時刻を進め、期限に達した sleep を再開させる。
    func advance(by duration: Swift.Duration) {
        let dueSleepers: [Sleeper] = lock.withLock {
            currentInstant = currentInstant.advanced(by: duration)
            let now = currentInstant
            let due = sleepers.filter { $0.deadline <= now }
            sleepers.removeAll { $0.deadline <= now }
            return due
        }
        for sleeper in dueSleepers {
            sleeper.continuation.resume()
        }
    }
}
