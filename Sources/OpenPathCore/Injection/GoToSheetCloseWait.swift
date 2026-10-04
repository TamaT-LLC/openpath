/// 確定した移動先シートが閉じたかの判定（Issue #95）。
public enum GoToSheetClosure: String, Equatable, Sendable {
    /// 閉じた（確定した入力欄が消えたか、注入先のウィンドウからその入力欄が見つからなくなった）。確定は届いている。
    case closed
    /// 期限までに閉じなかった。確定（Return・「移動」の押下）が届いておらず、パネルは移動していない。
    case stillOpen
    /// 閉じたかを確かめられない（確定した入力欄を見つけていない・探せない）。
    case unavailable
}

/// 移動先シートが閉じるのを待つ時間。
public struct GoToSheetCloseTiming: Equatable, Sendable {
    /// 閉じるのを待つ上限（確定から数える）。
    public let waitLimit: Duration
    /// 確かめ直す間隔。
    public let pollInterval: Duration
    /// 1 回の確認で、注入先のウィンドウから移動先シートの入力欄を探す走査の上限。
    public let lookupLimit: Duration

    public init(waitLimit: Duration, pollInterval: Duration, lookupLimit: Duration) {
        self.waitLimit = waitLimit
        self.pollInterval = pollInterval
        self.lookupLimit = lookupLimit
    }

    /// macOS 27 の自プロセスのパネルでは、Return から「開く」が押せる状態に戻る（移動先シートが閉じた後）まで約 410ms かかった（Issue #89）。
    /// これに余裕を持たせて 600ms まで待つ。主方式と副方式の両方で閉じずに諦める最も遅い経路（③ で約 900ms に出たシート）でも、
    /// 失敗は AppCoordinator の全体タイムアウト（2.5 秒）の前に返る（PathInjectionFlowSheetCloseTests）。
    public static let standard = GoToSheetCloseTiming(
        waitLimit: .milliseconds(600),
        pollInterval: .milliseconds(50),
        lookupLimit: .milliseconds(150)
    )
}

/// 確定（Return・「移動」の押下）の後に、移動先シートが閉じるのを待つ（Issue #95）。
///
/// 確定のキーが移動先シートに届かなければ、シートは残ったままパネルは移動しない（macOS 26.6.2 の VS Code で、
/// 先に開いた移動先シートへ注入先のプロセス経由で送った Return が届かなかった）。Return を送れたことだけで成功とせず、
/// 確定の直後から 50ms 間隔で、シートが閉じたかを確かめる。
/// - 確定した入力欄の要素が消えた（AX の要素が無効になった）か、注入先のウィンドウ（とそのシート）を探し直して
///   その入力欄が見つからなければ `.closed`。閉じたシートが破棄されずに残っても、ウィンドウから外れていれば閉じたとみなす。
///   確定した入力欄を AXIdentifier で特定していたのに、手掛かりの弱い入力欄（placeholder 等）しか見つからない場合も、
///   パネルの別の入力欄と取り違えないよう `.closed` とする。
/// - 期限までに閉じなければ `.stillOpen`。呼び出し側は成功とせず、副方式へ回すかエラーにする。
/// - 確定した入力欄を見つけていない・一度も確かめられなかった（探すのに失敗し続けた）場合は `.unavailable`。
///   呼び出し側は確かめられないため、従来どおり成功とする。
/// - 判定と待った時間を debug ログに残す（パスは含まない）。
@MainActor
public final class GoToSheetCloseWait {
    /// 1 回の確認の結果。
    private enum Observation {
        case closed
        case open
        /// 探せなかった（走査の期限切れ・AX の失敗）。
        case unknown
    }

    private let locator: any GoToFieldLocating
    private let timing: GoToSheetCloseTiming
    private let clock: any Clock<Duration>

    /// - Parameters:
    ///   - locator: 移動先シートの入力欄を探す（確定前の確認・副方式と同じもの）。注入の最初に記録したウィンドウの中を探す。
    ///   - clock: 待機に使う。テストでは実時間を待たない Clock を渡す。
    public init(
        locator: any GoToFieldLocating,
        timing: GoToSheetCloseTiming = .standard,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.locator = locator
        self.timing = timing
        self.clock = clock
    }

    /// 確定の直後に呼び、移動先シートが閉じるまで待って判定を返す。最初の確認は待たずに行う。
    /// - Parameter controls: 確定した入力欄。nil なら確かめずに `.unavailable` を返す。
    /// - Throws: キャンセル時は `CancellationError`。AX の失敗は投げずに、その回は分からないものとして確かめ続ける。
    public func waitUntilClosed(controls: GoToFieldControls?) async throws -> GoToSheetClosure {
        try Task.checkCancellation()
        guard let controls else {
            Log.debug("確定後の移動先シート: 確定した入力欄を見つけていないため、閉じたかを確かめません")
            return .unavailable
        }
        let timeline = ElapsedTimeline(clock: clock)
        var hasSeenOpen = false
        var checkCount = 0
        while true {
            let observation = try await observe(controls, on: timeline)
            checkCount += 1
            if case .closed = observation {
                log(.closed, elapsed: timeline.elapsed, checkCount: checkCount)
                return .closed
            }
            if case .open = observation {
                hasSeenOpen = true
            }
            if timeline.elapsed + timing.pollInterval > timing.waitLimit {
                let closure: GoToSheetClosure = hasSeenOpen ? .stillOpen : .unavailable
                log(closure, elapsed: timeline.elapsed, checkCount: checkCount)
                return closure
            }
            try await timeline.sleep(untilElapsed: timeline.elapsed + timing.pollInterval)
        }
    }

    /// 要素が消えたかの読み取り（AX 1 回）で分かれば、探し直さない。
    private func observe(_ controls: GoToFieldControls, on timeline: ElapsedTimeline) async throws -> Observation {
        let hasDisappeared = await controls.field.hasDisappeared()
        try Task.checkCancellation()
        if hasDisappeared {
            return .closed
        }
        let located: GoToFieldControls?
        do {
            located = try await withScanCutoff(at: timeline.elapsed + timing.lookupLimit, on: timeline) { cutoff in
                try await locator.locateGoToField(cutoff: cutoff)
            }
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
            }
            return .unknown
        }
        guard let located else { return .closed }
        if controls.evidence == .pathFieldIdentifier, located.evidence != .pathFieldIdentifier {
            return .closed
        }
        return .open
    }

    private func log(_ closure: GoToSheetClosure, elapsed: Duration, checkCount: Int) {
        Log.debug("確定後の移動先シート: \(closure.rawValue)（待った時間 \(InjectionLogFormat.milliseconds(elapsed))、確認 \(checkCount) 回）")
    }
}
