/// 「試してみる」のダイアログを出した osascript のプロセスの状態（前面に出せるか）。
public enum TrialPanelProcessState: Sendable, Equatable {
    /// まだアプリとして登録されていない（`NSRunningApplication` が無い）
    case notRegistered
    /// 登録されたが、まだウインドウを持てない（`activationPolicy == .prohibited`）。この間は前面に出せない
    case backgroundOnly
    /// ダイアログを出せる状態（UIElement）になったが、前面に出ていない
    case inactive
    /// 前面に出ている
    case active
    /// 終了した（ダイアログが閉じられた）
    case exited
}

/// osascript を前面に出すまでの待ち方（Issue #72）。
///
/// osascript は起動から 0.1 秒ほどでアプリとして登録されるが、ダイアログを出す直前（macOS 27 の実測で起動から
/// 0.6〜1.9 秒）までは `activationPolicy` が prohibited で、その間に前面に出そうとしても断られる。
/// UIElement に変わってからダイアログが出るまでは 50〜70ms のため、その間に前面に出せるよう細かく確かめる。
public struct TrialPanelActivationTiming: Sendable, Equatable {
    /// 状態を確かめる間隔
    public let pollInterval: Duration
    /// 前面に出す要求を送ってから、前面に出たかを確かめて次の要求を送るまでの間隔
    public let retryInterval: Duration
    /// 前面に出す要求を送る上限の回数
    public let maxAttempts: Int
    /// 起動してから前面に出るのを待つ上限。osascript の起動が遅い場合（初回の読み込みなど）に備えて長めにとる
    public let timeout: Duration

    public init(pollInterval: Duration, retryInterval: Duration, maxAttempts: Int, timeout: Duration) {
        self.pollInterval = pollInterval
        self.retryInterval = retryInterval
        self.maxAttempts = maxAttempts
        self.timeout = timeout
    }

    public static let standard = TrialPanelActivationTiming(
        pollInterval: .milliseconds(50),
        retryInterval: .milliseconds(200),
        maxAttempts: 5,
        timeout: .seconds(10)
    )
}

/// 前面に出す処理の結果。ログに残す。
public struct TrialPanelActivationOutcome: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        /// 前面に出た
        case activated
        /// 前面に出る前にダイアログが閉じられた
        case exited
        /// 期限（試行の上限・待ち時間の上限）までに前面に出せなかった。`lastState` は最後に確かめた状態
        case notActivated(lastState: TrialPanelProcessState)
    }

    public let status: Status
    /// 前面に出す要求を送った回数
    public let attempts: Int
    /// 前面に出す処理を始めてからの経過時間
    public let elapsed: Duration

    public init(status: Status, attempts: Int, elapsed: Duration) {
        self.status = status
        self.attempts = attempts
        self.elapsed = elapsed
    }

    /// 前面に出せなかったか。利用者がダイアログをクリックする必要がある
    public var needsUserAction: Bool {
        if case .notActivated = status {
            return true
        }
        return false
    }

    /// ログのメッセージ。パスは含めない
    public var logMessage: String {
        let detail = "試行 \(attempts) 回、\(Self.milliseconds(elapsed))ms"
        switch status {
        case .activated:
            return "「試してみる」のダイアログを前面に出しました（\(detail)）"
        case .exited:
            return "「試してみる」のダイアログは前面に出る前に閉じられました（\(detail)）"
        case .notActivated(let lastState):
            return "「試してみる」のダイアログを前面に出せませんでした（\(detail)、最後の状態: \(lastState)）。"
                + "ダイアログをクリックするとパレットが出ます"
        }
    }

    private static let attosecondsPerMillisecond: Int64 = 1_000_000_000_000_000
    private static let millisecondsPerSecond: Int64 = 1_000

    /// ミリ秒（切り捨て）
    private static func milliseconds(_ duration: Duration) -> Int64 {
        let components = duration.components
        return components.seconds * millisecondsPerSecond + components.attoseconds / attosecondsPerMillisecond
    }
}

/// osascript を前面に出すまでの待ち合わせと再試行の判定（Issue #72）。AppKit から切り離した純粋な状態機械。
///
/// 状態を確かめるたびに `next(observing:at:)` を呼び、返った行動に従う。
/// - 登録前・prohibited の間は待つ（この間の要求は断られるため、試行に数えない）
/// - 前面に出せる状態になったら要求を送り、`retryInterval` の後もまだ前面に出ていなければ送り直す
/// - 前面に出た・閉じられた・試行の上限・待ち時間の上限で終える
///
/// 前面に出たかは要求の戻り値ではなく、その後に確かめた状態で判断する（要求を受け付けても前面に出ないことがあるため）。
public struct TrialPanelActivation: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        /// 次に確かめるまで待つ
        case wait
        /// 前面に出す要求を送る
        case activate
        /// 終える
        case finish(TrialPanelActivationOutcome)
    }

    public let timing: TrialPanelActivationTiming
    /// 前面に出す要求を送った回数
    public private(set) var attempts = 0
    /// 最後に要求を送った時点の経過時間
    private var lastAttemptElapsed: Duration?

    public init(timing: TrialPanelActivationTiming = .standard) {
        self.timing = timing
    }

    /// 状態を確かめた結果から、次の行動を決める。
    /// - Parameters:
    ///   - state: 確かめた状態
    ///   - elapsed: 前面に出す処理を始めてからの経過時間
    public mutating func next(observing state: TrialPanelProcessState, at elapsed: Duration) -> Action {
        switch state {
        case .active:
            return finish(.activated, at: elapsed)
        case .exited:
            return finish(.exited, at: elapsed)
        case .notRegistered, .backgroundOnly, .inactive:
            break
        }
        // 直前の要求が反映されるのを待つ
        if let lastAttemptElapsed, elapsed - lastAttemptElapsed < timing.retryInterval {
            return .wait
        }
        if attempts >= timing.maxAttempts || elapsed >= timing.timeout {
            return finish(.notActivated(lastState: state), at: elapsed)
        }
        guard state == .inactive else {
            return .wait
        }
        attempts += 1
        lastAttemptElapsed = elapsed
        return .activate
    }

    private func finish(_ status: TrialPanelActivationOutcome.Status, at elapsed: Duration) -> Action {
        .finish(TrialPanelActivationOutcome(status: status, attempts: attempts, elapsed: elapsed))
    }
}
