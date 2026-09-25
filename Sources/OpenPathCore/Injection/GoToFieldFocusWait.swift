/// 移動先シートの入力欄が、キー入力の受け先（フォーカス）になったかの判定（Issue #74）。
public enum GoToFieldFocus: String, Equatable, Sendable {
    /// 入力欄がフォーカスを持っている。キー入力（⌘A / ⌘V / Return）は入力欄に届く。
    case focused
    /// 期限までに入力欄がフォーカスを持たなかった。キー入力は入力欄に届かないおそれがある。
    case notFocused
    /// 待っている間に入力欄が消えた（移動先シートが閉じた）。キー入力はパネル本体に届いてしまう。
    case fieldGone
    /// 入力欄が見つからない・フォーカスを読めない。確かめられない。
    case unavailable
}

/// 入力欄のフォーカスを待つ時間。
public struct GoToFieldFocusTiming: Equatable, Sendable {
    /// 入力欄を探す走査の上限。
    public let lookupLimit: Duration
    /// フォーカスを待つ上限。入力欄を探す時間も含め、待ち始めてから数える。
    public let waitLimit: Duration
    /// 確かめ直す間隔。
    public let pollInterval: Duration

    public init(lookupLimit: Duration, waitLimit: Duration, pollInterval: Duration) {
        self.lookupLimit = lookupLimit
        self.waitLimit = waitLimit
        self.pollInterval = pollInterval
    }

    /// シート待ち（最大 600ms）・確定前の確認（最大 350ms）・「開く」の待機（300ms）と合わせても、
    /// AppCoordinator の全体タイムアウト（1.5 秒）を大きく超えない長さにする。
    public static let standard = GoToFieldFocusTiming(
        lookupLimit: .milliseconds(150),
        waitLimit: .milliseconds(250),
        pollInterval: .milliseconds(50)
    )
}

/// フォーカスを待った結果。
public struct GoToFieldFocusResult {
    public let focus: GoToFieldFocus
    /// 見つけた入力欄。確定前の確認（`GoToSheetSubmitGate`）で探し直さずに使う。見つからなければ nil。
    public let controls: GoToFieldControls?

    public init(focus: GoToFieldFocus, controls: GoToFieldControls?) {
        self.focus = focus
        self.controls = controls
    }
}

/// キー入力（⌘A / ⌘V / Return）を送る前に、移動先シートの入力欄がフォーカスを持つまで待つ（Issue #74）。
///
/// 移動先シートが AX に現れた直後は、入力欄がまだキー入力の受け先になっていないことがある。その間に送ったキー入力は
/// 入力欄に届かない（macOS 26.6.2 の QA で、シートの検知の 1ms 後に送った ⌘A / ⌘V が効かず、入力欄に前回の移動先が残った）。
/// - 入力欄の kAXFocused を間隔を空けて読み、true になったら `.focused` を返す。期限までにならなければ `.notFocused`。
/// - 待っている間に入力欄が消えたら `.fieldGone`（キー入力はパネル本体に届き、Return は「開く」を押してしまうおそれがある）。
/// - 入力欄が見つからない・フォーカスを読めなければ `.unavailable`（確かめられないため、呼び出し側は従来どおり進める）。
/// - AX でフォーカスを与えることはしない（呼び出し側が判断する）。
/// - 判定と待った時間を debug ログに残す（QA での切り分け用。パスは含まない）。
@MainActor
public final class GoToFieldFocusWait {
    private let locator: any GoToFieldLocating
    private let timing: GoToFieldFocusTiming
    private let clock: any Clock<Duration>

    /// - Parameters:
    ///   - locator: 移動先シートの入力欄を探す（確定前の確認・副方式と同じもの）。
    ///   - clock: 待機に使う。テストでは実時間を待たない Clock を渡す。
    public init(
        locator: any GoToFieldLocating,
        timing: GoToFieldFocusTiming = .standard,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.locator = locator
        self.timing = timing
        self.clock = clock
    }

    /// 入力欄がフォーカスを持つまで待ち、判定を返す。
    /// - Parameter knownControls: 見つけ済みの入力欄（副方式）。nil なら探す（主方式）。
    /// - Throws: キャンセル時は `CancellationError`。AX の失敗は投げずに `.unavailable` を返す。
    public func waitUntilFocused(controls knownControls: GoToFieldControls? = nil) async throws -> GoToFieldFocusResult {
        try Task.checkCancellation()
        let timeline = ElapsedTimeline(clock: clock)
        let lookupLimit = min(timing.lookupLimit, timing.waitLimit)
        guard let controls = try await GoToFieldLookup.resolve(
            knownControls, with: locator, within: lookupLimit, on: timeline, context: "入力欄のフォーカス"
        ) else {
            Log.debug("入力欄のフォーカス: 移動先シートの入力欄が見つからないため確かめません")
            return GoToFieldFocusResult(focus: .unavailable, controls: nil)
        }
        var readCount = 0
        while true {
            let focus = try await readFocus(of: controls.field)
            readCount += 1
            let isLastCheck = timeline.elapsed + timing.pollInterval > timing.waitLimit
            if focus != .notFocused || isLastCheck {
                Log.debug("入力欄のフォーカス: \(focus.rawValue)（待った時間 \(InjectionLogFormat.milliseconds(timeline.elapsed))、確認 \(readCount) 回）")
                return GoToFieldFocusResult(focus: focus, controls: controls)
            }
            try await timeline.sleep(untilElapsed: timeline.elapsed + timing.pollInterval)
        }
    }

    private func readFocus(of field: any PanelElementOperating) async throws -> GoToFieldFocus {
        do {
            return try await field.isFocused() ? .focused : .notFocused
        } catch {
            try Task.checkCancellation()
            // 要素が消えたこと（invalidUIElement）は、アダプタが panelGone として伝える
            if error as? InjectionError == .panelGone {
                return .fieldGone
            }
            Log.debug("入力欄のフォーカス: 読めませんでした（\(error)）")
            return .unavailable
        }
    }
}

/// 移動先シートの入力欄を探す（フォーカス待ちと確定前の確認で共通）。
@MainActor
enum GoToFieldLookup {
    /// knownControls があればそのまま返し、無ければ limit までに探す。
    /// - Returns: 見つからない・探せなければ（AX の失敗・期限切れ）nil。
    /// - Throws: キャンセル時は `CancellationError`。
    static func resolve(
        _ knownControls: GoToFieldControls?,
        with locator: any GoToFieldLocating,
        within limit: Duration,
        on timeline: ElapsedTimeline,
        context: String
    ) async throws -> GoToFieldControls? {
        if let knownControls {
            return knownControls
        }
        do {
            return try await withScanCutoff(at: timeline.elapsed + limit, on: timeline) { cutoff in
                try await locator.locateGoToField(cutoff: cutoff)
            }
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
            }
            Log.debug("\(context): 移動先シートを探せませんでした（\(type(of: error))）")
            return nil
        }
    }
}
