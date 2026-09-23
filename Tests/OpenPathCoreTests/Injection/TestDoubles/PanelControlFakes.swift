import OpenPathCore

/// 注入先の確認を記録し、指定した回数目以降の確認で注入先を無効にする。
@MainActor
final class TargetGuardFake: InjectionTargetGuarding {
    private let log: InjectionEventLog
    /// 確認を共有のログに記録するか。主方式の既存テストのタイムラインを変えないよう、既定では記録しない。
    var logsChecks = false
    /// この回数（0 始まり）目以降の確認で返す状態。nil なら常に `.available`。
    var invalidation: (fromCheck: Int, status: InjectionTargetStatus)?
    /// 記録で投げるエラー。
    var captureError: (any Error)?
    /// 確認で投げるエラー。
    var checkError: (any Error)?
    private(set) var captureCount = 0
    private(set) var checkCount = 0

    init(log: InjectionEventLog) {
        self.log = log
    }

    func captureTarget(cutoff: ScanCutoff) async throws {
        log.record(.captureTarget)
        captureCount += 1
        if let captureError {
            throw captureError
        }
        try cutoff.throwIfReached()
    }

    func currentStatus(cutoff: ScanCutoff) async throws -> InjectionTargetStatus {
        let checkIndex = checkCount
        checkCount += 1
        if logsChecks {
            log.record(.targetCheck)
        }
        if let checkError {
            throw checkError
        }
        try cutoff.throwIfReached()
        guard let invalidation, checkIndex >= invalidation.fromCheck else { return .available }
        return invalidation.status
    }
}

/// パネル内の要素（入力欄・ボタン）。AX 操作を記録する。
@MainActor
final class PanelElementFake: PanelElementOperating {
    let name: String
    private let log: InjectionEventLog
    var setValueError: (any Error)?
    var pressError: (any Error)?
    var confirmError: (any Error)?
    /// 押下・確定で要素が消えるか（シートやパネルが閉じる）。
    var disappearsWhenActivated = false
    /// 要素が消えているか。
    var isGone = false
    private(set) var value: String?

    init(_ name: String, log: InjectionEventLog) {
        self.name = name
        self.log = log
    }

    func setValue(_ value: String) async throws {
        log.record(.setValue(element: name, value: value))
        if let setValueError {
            throw setValueError
        }
        self.value = value
    }

    func press() async throws {
        log.record(.press(element: name))
        try activate(failingWith: pressError)
    }

    func confirm() async throws {
        log.record(.confirmField(element: name))
        try activate(failingWith: confirmError)
    }

    func hasDisappeared() async -> Bool {
        isGone
    }

    private func activate(failingWith error: (any Error)?) throws {
        if disappearsWhenActivated {
            isGone = true
        }
        if let error {
            throw error
        }
    }
}

/// 要素探しの走査を数回の AX 操作に分けて時間を進め、実物と同じく操作の直前ごとに打ち切り条件を確かめる。
@MainActor
private func simulateAXScan(clock: VirtualClock, log: InjectionEventLog, taking latency: Duration, cutoff: ScanCutoff) throws {
    let axOperationsPerScan = 4
    for _ in 0..<axOperationsPerScan {
        do {
            try cutoff.throwIfReached()
        } catch {
            log.record(.scanCutOff)
            throw error
        }
        clock.advance(by: latency / axOperationsPerScan)
    }
}

/// 副方式の入力欄探し。field が nil なら見つからない。
@MainActor
final class GoToFieldLocatorFake: GoToFieldLocating {
    private let clock: VirtualClock
    private let log: InjectionEventLog
    var field: PanelElementFake?
    var goButton: PanelElementFake?
    /// 1 回の走査にかかる時間。
    var lookupLatency: Duration = .zero
    var error: (any Error)?
    /// 設定すると、走査の途中でテストから再開されるまで止まる。
    var suspension: Suspension?

    init(clock: VirtualClock, log: InjectionEventLog) {
        self.clock = clock
        self.log = log
    }

    func locateGoToField(cutoff: ScanCutoff) async throws -> GoToFieldControls? {
        log.record(.lookUpGoToField)
        if let suspension {
            await suspension.suspend()
        }
        if let error {
            throw error
        }
        try simulateAXScan(clock: clock, log: log, taking: lookupLatency, cutoff: cutoff)
        guard let field else { return nil }
        return GoToFieldControls(field: field, goButton: goButton)
    }
}

/// auto_confirm の「開く」ボタン探し。button が nil なら見つからない。
@MainActor
final class OpenButtonLocatorFake: OpenButtonLocating {
    private let clock: VirtualClock
    private let log: InjectionEventLog
    var button: PanelElementFake?
    /// 1 回の走査にかかる時間。
    var lookupLatency: Duration = .zero
    var error: (any Error)?
    /// 設定すると、走査の途中でテストから再開されるまで止まる。
    var suspension: Suspension?

    init(clock: VirtualClock, log: InjectionEventLog) {
        self.clock = clock
        self.log = log
    }

    func locateOpenButton(cutoff: ScanCutoff) async throws -> (any PanelElementOperating)? {
        log.record(.lookUpOpenButton)
        if let suspension {
            await suspension.suspend()
        }
        if let error {
            throw error
        }
        try simulateAXScan(clock: clock, log: log, taking: lookupLatency, cutoff: cutoff)
        return button
    }
}
