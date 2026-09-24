/// 移動先シートの状態（入力欄の値と、候補リストで選ばれている候補）。
public struct GoToSheetState: Equatable, Sendable {
    /// 入力欄の値。読めなければ nil。
    public var fieldValue: String?
    /// 候補リストで選ばれている候補のパス。リストが無い・選択が無い・読めなければ nil。
    public var selectedSuggestion: String?

    public init(fieldValue: String?, selectedSuggestion: String?) {
        self.fieldValue = fieldValue
        self.selectedSuggestion = selectedSuggestion
    }

    /// 移動先 path へ確定してよいか。パスは normalizer で揃えてから比べる（`~` の展開・末尾の `/`、正準等価）。
    public func readiness(for path: String, normalizer: InjectionPathNormalizer) -> GoToSheetReadiness {
        guard let fieldValue else { return .unavailable }
        let expected = normalizer.normalize(path)
        guard normalizer.normalize(fieldValue) == expected else { return .fieldMismatch }
        guard let selectedSuggestion, normalizer.normalize(selectedSuggestion) != expected else { return .ready }
        return .suggestionNotUpdated
    }
}

/// 移動先シートを確定してよいかの判定（Issue #74）。
public enum GoToSheetReadiness: String, Equatable, Sendable {
    /// 入力欄の値が移動先で、候補の選択も移動先か選択が無い。
    case ready
    /// 入力欄の値は移動先だが、候補リストが前の値の候補を選んだまま（リストの出し直しが追いついていない）。
    case suggestionNotUpdated
    /// 入力欄の値が移動先でない（貼り付けが反映されていない・前回の値が残っている等）。確定すると別の場所へ移動する。
    case fieldMismatch
    /// 移動先シートを AX で読めない（入力欄が見つからない・値を読めない）。確かめられない。
    case unavailable
}

/// 確定前の確認の待ち時間。
public struct GoToSheetSubmitTiming: Equatable, Sendable {
    /// 移動先シートの入力欄を探す走査の上限。
    public let lookupLimit: Duration
    /// 入力欄の値と候補の選択が移動先に追いつくのを待つ上限（探した後から数える）。
    public let settleLimit: Duration
    /// 確かめ直す間隔。
    public let pollInterval: Duration

    public init(lookupLimit: Duration, settleLimit: Duration, pollInterval: Duration) {
        self.lookupLimit = lookupLimit
        self.settleLimit = settleLimit
        self.pollInterval = pollInterval
    }

    /// macOS 27 では、貼り付けから候補リストの出し直しまで 200〜300ms かかった（Issue #74）。
    /// 主方式の貼り付け後の待機（100ms）と合わせて貼り付けから約 350ms まで待つ。
    /// シート待ち（最大 600ms）と「開く」の待機（300ms）を足しても、AppCoordinator の全体タイムアウト（1.5 秒）に収まる長さにする。
    public static let standard = GoToSheetSubmitTiming(
        lookupLimit: .milliseconds(150),
        settleLimit: .milliseconds(250),
        pollInterval: .milliseconds(50)
    )
}

/// 移動先シートを確定する（Return・「移動」の押下）前に、入力欄の値と候補の選択が移動先と一致するのを待つ（Issue #74）。
///
/// - 入力欄の値が移動先にならなければ `.fieldMismatch` を返す。貼り付けが効かずに前回の値が残ったまま確定すると、
///   パネルが前回の場所へ移動してしまうため、呼び出し側は確定しない。
/// - macOS 13 以降の移動先シートは、入力に合わせて候補リストを出し直すまで、前の値の候補を選んだままにする（macOS 27 で 200〜300ms）。
///   確定で選ばれた候補の方へ移動する OS に備え、候補の選択が移動先に追いつくまで待つ。期限までに追いつかなければ
///   `.suggestionNotUpdated` を返し、呼び出し側はそのまま確定する（リストを出し直さない入力もある。macOS 27 の確定は入力欄の値を使う）。
/// - 移動先シートを AX で読めなければ `.unavailable` を返す。呼び出し側は確かめずに確定する（従来どおり）。
/// - 判定と、確定前の入力欄の値・候補の選択を debug ログに残す（QA での切り分け用）。
@MainActor
public final class GoToSheetSubmitGate {
    private let locator: any GoToFieldLocating
    private let normalizer: InjectionPathNormalizer
    private let timing: GoToSheetSubmitTiming
    private let clock: any Clock<Duration>

    /// - Parameters:
    ///   - locator: 移動先シートの入力欄と候補リストを探す（副方式と同じもの）。
    ///   - normalizer: 入力欄の値・候補のパスと移動先を比べる前に揃える。
    ///   - clock: 待機に使う。テストでは実時間を待たない Clock を渡す。
    public init(
        locator: any GoToFieldLocating,
        normalizer: InjectionPathNormalizer = InjectionPathNormalizer(),
        timing: GoToSheetSubmitTiming = .standard,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.locator = locator
        self.normalizer = normalizer
        self.timing = timing
        self.clock = clock
    }

    /// 入力欄の値と候補の選択が path になるまで待ち、判定を返す。
    /// - Parameter controls: 見つけ済みの入力欄（副方式）。nil なら探す（主方式）。
    /// - Throws: キャンセル時は `CancellationError`。AX の失敗は投げずに `.unavailable` を返す（確定を止める理由にしない）。
    public func waitUntilReady(path: String, controls knownControls: GoToFieldControls? = nil) async throws -> GoToSheetReadiness {
        try Task.checkCancellation()
        let timeline = ElapsedTimeline(clock: clock)
        guard let controls = try await resolveControls(knownControls, on: timeline) else {
            Log.debug("確定前の確認: 移動先シートの入力欄が見つからないため確かめません")
            return .unavailable
        }
        let deadline = timeline.elapsed + timing.settleLimit
        while true {
            let state = try await readState(of: controls)
            let readiness = state.readiness(for: path, normalizer: normalizer)
            let isLastCheck = timeline.elapsed + timing.pollInterval > deadline
            if readiness == .ready || readiness == .unavailable || isLastCheck {
                log(readiness, state: state, elapsed: timeline.elapsed)
                return readiness
            }
            try await timeline.sleep(untilElapsed: timeline.elapsed + timing.pollInterval)
        }
    }

    private func resolveControls(_ knownControls: GoToFieldControls?, on timeline: ElapsedTimeline) async throws -> GoToFieldControls? {
        if let knownControls {
            return knownControls
        }
        do {
            return try await withScanCutoff(at: timeline.elapsed + timing.lookupLimit, on: timeline) { cutoff in
                try await locator.locateGoToField(cutoff: cutoff)
            }
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
            }
            Log.debug("確定前の確認: 移動先シートを探せませんでした（\(type(of: error))）")
            return nil
        }
    }

    /// 候補の選択を読めなくても、入力欄の値だけで判定する。
    private func readState(of controls: GoToFieldControls) async throws -> GoToSheetState {
        let fieldValue: String?
        do {
            fieldValue = try await controls.field.value()
        } catch {
            try Task.checkCancellation()
            fieldValue = nil
        }
        var selectedSuggestion: String?
        if let suggestionList = controls.suggestionList {
            selectedSuggestion = try? await suggestionList.selectedPath()
            try Task.checkCancellation()
        }
        return GoToSheetState(fieldValue: fieldValue, selectedSuggestion: selectedSuggestion)
    }

    private func log(_ readiness: GoToSheetReadiness, state: GoToSheetState, elapsed: Duration) {
        Log.debug("確定前の確認: \(readiness.rawValue)（確認にかけた時間 \(InjectionLogFormat.milliseconds(elapsed))）")
        Log.debugPath("確定前の移動先シートの入力欄", path: state.fieldValue ?? "（読めず）")
        Log.debugPath("確定前の移動先シートの候補の選択", path: state.selectedSuggestion ?? "（なし）")
    }
}

/// 注入の debug ログの書式。
enum InjectionLogFormat {
    /// 経過時間をミリ秒の整数で表す（例: `350ms`）。
    static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        let attosecondsPerMillisecond: Int64 = 1_000_000_000_000_000
        let millisecondsPerSecond: Int64 = 1_000
        return "\(seconds * millisecondsPerSecond + attoseconds / attosecondsPerMillisecond)ms"
    }
}
