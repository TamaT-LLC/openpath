/// 一定間隔で値を読み取り、変化したときだけ通知する。
///
/// 待機処理を差し替えられるため、実時間を待たずに間隔と通知条件をテストできる。
public struct ValueChangePoller<Value: Equatable & Sendable>: Sendable {
    /// 指定時間だけ待機する。キャンセル時は CancellationError を投げること。
    public typealias Sleep = @Sendable (Duration) async throws -> Void
    /// 現在の値を読み取る。
    public typealias Read = @Sendable () async -> Value

    /// 読み取りの間隔。
    public let interval: Duration
    private let sleep: Sleep
    private let read: Read

    /// - Parameters:
    ///   - interval: 読み取りの間隔。
    ///   - sleep: 待機処理。省略時は `Task.sleep(for:)`。
    ///   - read: 値の読み取り処理。
    public init(
        interval: Duration,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        read: @escaping Read
    ) {
        self.interval = interval
        self.sleep = sleep
        self.read = read
    }

    /// `interval` ごとに値を読み取り、直前の値から変化した値だけを流す。
    ///
    /// 読み取りの前に毎回 `interval` だけ待つため、変化は `interval` 以内に通知される。
    /// 購読をやめる（イテレーションのキャンセルやストリームの破棄）とポーリングを止める。
    /// - Parameter initial: 比較の起点になる現在の値。この値自体は流さない。
    public func changes(from initial: Value) -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream<Value>.makeStream()
        let pollingTask = Task { [interval, sleep, read] in
            var detector = ValueChangeDetector(initial: initial)
            while !Task.isCancelled {
                do {
                    try await sleep(interval)
                } catch {
                    break
                }
                if let changed = detector.update(await read()) {
                    continuation.yield(changed)
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in
            pollingTask.cancel()
        }
        return stream
    }
}
