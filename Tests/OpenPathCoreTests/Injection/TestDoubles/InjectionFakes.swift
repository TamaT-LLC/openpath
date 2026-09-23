import OpenPathCore

/// キャンセルできない処理（AX の呼び出し等）の途中で止め、テストから再開させるための待ち合わせ。
@MainActor
final class Suspension {
    private var continuation: CheckedContinuation<Void, Never>?
    private let waiter = ConditionWaiter()

    var isSuspended: Bool {
        continuation != nil
    }

    /// `resume()` されるまで戻らない。キャンセルにも応じない。
    func suspend() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            waiter.notify()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }

    func waitUntilSuspended() async {
        await waiter.wait { self.isSuspended }
    }
}

/// 送られたキー操作を記録する。
@MainActor
final class KeyboardSpy: KeyStrokePosting {
    private let log: InjectionEventLog
    /// 送出に失敗させるキー操作。
    var failingKeyStrokes: Set<InjectionKeyStroke> = []
    /// 送出を記録した直後に呼ばれる（送出直後のキャンセルを再現するため）。
    var onPost: ((InjectionKeyStroke) -> Void)?

    init(log: InjectionEventLog) {
        self.log = log
    }

    func post(_ keyStroke: InjectionKeyStroke) throws {
        guard !failingKeyStrokes.contains(keyStroke) else { throw AdapterFailure() }
        log.record(.key(keyStroke))
        onPost?(keyStroke)
    }
}

/// 指定した時刻以降の判定で移動先シートが出たことにする。
/// AX の走査を数回の AX 操作に分けて時間を進め、実物と同じく操作の直前ごとに打ち切り条件を確かめる。
@MainActor
final class SheetDetectorFake: GoToSheetDetecting {
    private final class Probe: GoToSheetProbe {
        private let detector: SheetDetectorFake

        init(detector: SheetDetectorFake) {
            self.detector = detector
        }

        func isSheetShown(cutoff: ScanCutoff) async throws -> Bool {
            try await detector.check(cutoff: cutoff)
        }
    }

    /// 1 回の走査を何回の AX 操作に分けるか。
    private static let axOperationsPerScan = 4

    private let clock: VirtualClock
    private let log: InjectionEventLog
    /// この経過時間以降の判定でシートが出たことにする。nil なら最後まで出ない。
    var appearsAt: Duration?
    /// 基準の記録（1 回の走査）にかかる時間。
    var probeLatency: Duration = .zero
    /// 1 回の判定（走査）にかかる時間。
    var checkLatency: Duration = .zero
    /// makeProbe で投げるエラー。
    var probeError: (any Error)?
    /// 判定で投げるエラー。
    var checkError: (any Error)?
    /// 設定すると、判定の途中でテストから再開されるまで止まる。
    var checkSuspension: Suspension?
    /// 途中で止めた判定の結果。
    var suspendedCheckResult = false
    /// 途中で止めた判定が、再開後に打ち切り条件を確かめるか。
    var checksCutoffAfterSuspension = true
    /// 途中で止めた判定に渡された打ち切り条件（キャンセルが走査側から見えることを確かめるため）。
    private(set) var suspendedCheckCutoff: ScanCutoff?

    init(clock: VirtualClock, log: InjectionEventLog, appearsAt: Duration? = nil) {
        self.clock = clock
        self.log = log
        self.appearsAt = appearsAt
    }

    func makeProbe(cutoff: ScanCutoff) async throws -> any GoToSheetProbe {
        log.record(.makeProbe)
        if let probeError {
            throw probeError
        }
        try simulateScan(taking: probeLatency, cutoff: cutoff)
        return Probe(detector: self)
    }

    private func check(cutoff: ScanCutoff) async throws -> Bool {
        if let checkSuspension {
            suspendedCheckCutoff = cutoff
            await checkSuspension.suspend()
            if checksCutoffAfterSuspension {
                try throwIfCutOff(cutoff)
            }
            log.record(.sheetCheck(isShown: suspendedCheckResult))
            return suspendedCheckResult
        }
        if let checkError {
            throw checkError
        }
        try simulateScan(taking: checkLatency, cutoff: cutoff)
        let isShown = appearsAt.map { clock.elapsed >= $0 } ?? false
        log.record(.sheetCheck(isShown: isShown))
        return isShown
    }

    private func simulateScan(taking latency: Duration, cutoff: ScanCutoff) throws {
        let operationLatency = latency / Self.axOperationsPerScan
        for _ in 0..<Self.axOperationsPerScan {
            try throwIfCutOff(cutoff)
            clock.advance(by: operationLatency)
        }
    }

    private func throwIfCutOff(_ cutoff: ScanCutoff) throws {
        do {
            try cutoff.throwIfReached()
        } catch {
            log.record(.scanCutOff)
            throw error
        }
    }
}

/// PathInjectionHooks の呼び出しを記録する。
@MainActor
final class HooksSpy {
    private let clock: VirtualClock
    private let log: InjectionEventLog
    /// didSubmitGoToSheet にかかる時間（auto_confirm の待機と AXPress）。
    var submitDuration: Duration = .zero
    /// didSubmitGoToSheet で投げるエラー。
    var submitError: (any Error)?
    /// 設定すると、didSubmitGoToSheet の途中でテストから再開されるまで止まる。
    var submitSuspension: Suspension?
    /// didSubmitGoToSheet の中で呼ばれる（注入中の外部の書き込みを再現するため）。
    var onSubmit: (() -> Void)?

    init(clock: VirtualClock, log: InjectionEventLog) {
        self.clock = clock
        self.log = log
    }

    var hooks: PathInjectionHooks {
        PathInjectionHooks(
            prepareForKeyEvents: { [self] in
                log.record(.prepareForKeyEvents)
            },
            didSubmitGoToSheet: { [self] autoConfirm in
                try await didSubmit(autoConfirm: autoConfirm)
            }
        )
    }

    private func didSubmit(autoConfirm: Bool) async throws {
        log.record(.didSubmitGoToSheet(autoConfirm: autoConfirm))
        onSubmit?()
        if let submitSuspension {
            await submitSuspension.suspend()
        }
        clock.advance(by: submitDuration)
        if let submitError {
            throw submitError
        }
    }
}

/// 実行中の Task を、その中から取り消す（操作の直後にキャンセルが届いた状況を再現する）。
func cancelCurrentTask() {
    withUnsafeCurrentTask { task in
        task?.cancel()
    }
}
