/// 生成時点からの経過時間で待ち合わせる時計。
/// `any Clock<Duration>` の Instant は存在型のままでは加算・比較できないため、経過時間に置き換えて扱う。
struct ElapsedTimeline: Sendable {
    private let readElapsed: @Sendable () -> Duration
    private let sleepUntilElapsed: @Sendable (Duration) async throws -> Void

    init<C: Clock<Duration>>(clock: C) {
        let origin = clock.now
        readElapsed = { origin.duration(to: clock.now) }
        sleepUntilElapsed = { elapsed in
            try await clock.sleep(until: origin.advanced(by: elapsed), tolerance: nil)
        }
    }

    /// 生成からの経過時間。
    var elapsed: Duration {
        readElapsed()
    }

    /// 経過時間が elapsed に達するまで待つ。既に過ぎていれば待たない。
    /// - Throws: キャンセルされた場合 `CancellationError`。
    func sleep(untilElapsed elapsed: Duration) async throws {
        try await sleepUntilElapsed(elapsed)
    }
}

/// 注入を 1 件ずつ実行するための待ち合わせ。
/// キャンセルされた注入が、キャンセルできない処理（AX の呼び出し）の完了を待って後始末している間に次の注入が始まると、
/// 次の注入がペーストボードを退避するときに前のパスを元の内容として取り込んでしまうため、前の注入の完了を待つ。
@MainActor
final class InjectionSerialGate {
    private var isOccupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// 先行する注入が `leave()` するまで待つ。
    func enter() async {
        guard isOccupied else {
            isOccupied = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// 次の待ち手に順番を渡す。待ち手が無ければ空ける。
    func leave() {
        guard !waiters.isEmpty else {
            isOccupied = false
            return
        }
        waiters.removeFirst().resume()
    }
}
