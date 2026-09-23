import Foundation

/// sleep すると実時間を待たずに、その期限まで時刻を進める Clock。
/// 注入の手順は 1 本の流れの中で待つだけなので、各操作が起きた時刻を決定的に検証できる。
/// `@unchecked Sendable` の根拠: 可変状態はすべて `lock` で保護している。
final class VirtualClock: Clock, @unchecked Sendable {
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

    private let lock = NSLock()
    private var currentInstant = Instant(offset: .zero)

    var now: Instant {
        lock.withLock { currentInstant }
    }

    var minimumResolution: Swift.Duration {
        .zero
    }

    /// 生成からの経過時間。
    var elapsed: Swift.Duration {
        now.offset
    }

    func sleep(until deadline: Instant, tolerance: Swift.Duration?) async throws {
        // Task.sleep と同じく、キャンセル済みなら待たずに CancellationError を投げる
        try Task.checkCancellation()
        lock.withLock {
            if currentInstant < deadline {
                currentInstant = deadline
            }
        }
    }

    /// AX の往復など、時間のかかる処理を表すために時刻を進める。
    func advance(by duration: Swift.Duration) {
        lock.withLock {
            currentInstant = currentInstant.advanced(by: duration)
        }
    }
}
