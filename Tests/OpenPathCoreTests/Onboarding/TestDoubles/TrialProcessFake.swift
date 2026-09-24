import OpenPathCore

/// 「試してみる」の osascript の状態を、仮想時計の時刻で進めるフェイク。
///
/// 既定の時刻は macOS 27 の実測（Issue #72）に合わせている: 起動から約 0.1 秒でアプリとして登録され（prohibited）、
/// 約 1 秒で UIElement に変わる。prohibited の間の要求は断られ、UIElement になってからの要求で前面に出る。
@MainActor
final class TrialProcessFake {
    private let clock: VirtualClock
    /// アプリとして登録される時刻
    var registeredAt: Duration = .milliseconds(100)
    /// UIElement に変わる（前面に出せるようになる）時刻
    var readyAt: Duration = .milliseconds(980)
    /// 終了する（ダイアログが閉じられる）時刻
    var exitedAt: Duration?
    /// 前面に出せる状態でも断る回数
    var refusalsRemaining = 0
    /// 前面に出ているか
    var isActive = false
    /// 前面に出す要求を受けた時刻
    private(set) var activationRequests: [Duration] = []

    init(clock: VirtualClock) {
        self.clock = clock
    }

    /// 仮想時計の現在時刻での状態
    func state() -> TrialPanelProcessState {
        let now = clock.elapsed
        if let exitedAt, now >= exitedAt {
            return .exited
        }
        if isActive {
            return .active
        }
        if now < registeredAt {
            return .notRegistered
        }
        if now < readyAt {
            return .backgroundOnly
        }
        return .inactive
    }

    /// 前面に出す要求を受ける。前面に出せる状態で、断る回数が残っていなければ前面に出る
    func activate() {
        activationRequests.append(clock.elapsed)
        guard state() == .inactive else { return }
        if refusalsRemaining > 0 {
            refusalsRemaining -= 1
            return
        }
        isActive = true
    }
}
