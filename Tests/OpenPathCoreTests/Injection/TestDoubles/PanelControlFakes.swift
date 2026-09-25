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
    /// 入力欄に入っている値。setValue と `simulateTyping(_:)` で変わる。
    private(set) var currentValue: String?
    /// 設定すると、値の読み取り（`value()`）はこれの結果を返す（時間とともに変わる値を再現する）。
    var valueProvider: (@MainActor () -> String?)?
    /// 値の読み取りで投げるエラー。
    var valueReadError: (any Error)?
    /// 値を読み取った回数。
    private(set) var valueReadCount = 0
    /// キー入力の受け先（フォーカス）か。`focusProvider` があればそちらを使う。
    var hasFocus = true
    /// 設定すると、フォーカスの読み取り（`isFocused()`）はこれの結果を返す（遅れて来るフォーカスを再現する）。
    var focusProvider: (@MainActor () -> Bool)?
    /// フォーカスの読み取りで投げるエラー。
    var focusReadError: (any Error)?
    /// AX でフォーカスを与えたとき（`focus()`）に投げるエラー。
    var focusRequestError: (any Error)?
    /// AX でフォーカスを与えたら、フォーカスを持つようになるか。
    var acceptsFocusRequest = true
    /// フォーカスを読み取った回数。
    private(set) var focusReadCount = 0

    init(_ name: String, log: InjectionEventLog) {
        self.name = name
        self.log = log
    }

    /// その時点でフォーカスを持っているか（キー入力が入力欄に届くかの判定に使う。読み取りの回数には数えない）。
    var isFocusedNow: Bool {
        focusProvider.map { $0() } ?? hasFocus
    }

    func setValue(_ value: String) async throws {
        log.record(.setValue(element: name, value: value))
        if let setValueError {
            throw setValueError
        }
        currentValue = value
    }

    /// キー入力（貼り付け）で値が変わったことにする。AX 操作ではないためログには残さない。
    func simulateTyping(_ value: String?) {
        currentValue = value
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

    func value() async throws -> String? {
        valueReadCount += 1
        if let valueReadError {
            throw valueReadError
        }
        return valueProvider.map { $0() } ?? currentValue
    }

    func isFocused() async throws -> Bool {
        focusReadCount += 1
        if let focusReadError {
            throw focusReadError
        }
        return isFocusedNow
    }

    func focus() async throws {
        log.record(.focusField(element: name))
        if let focusRequestError {
            throw focusRequestError
        }
        guard acceptsFocusRequest else { return }
        focusProvider = nil
        hasFocus = true
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

/// 移動先シートの候補リスト。選ばれている候補のパスを返す。
@MainActor
final class SuggestionListFake: GoToSuggestionListReading {
    /// 選ばれている候補のパス。
    var selectedPathProvider: @MainActor () -> String? = { nil }
    /// 読み取りで投げるエラー。
    var readError: (any Error)?

    func selectedPath() async throws -> String? {
        if let readError {
            throw readError
        }
        return selectedPathProvider()
    }
}

/// 移動先シートの入力欄探し。field が nil なら見つからない。
@MainActor
final class GoToFieldLocatorFake: GoToFieldLocating {
    private let clock: VirtualClock
    private let log: InjectionEventLog
    var field: PanelElementFake?
    var goButton: PanelElementFake?
    var suggestionList: SuggestionListFake?
    /// 探したことを共有のログに記録するか（主方式の確定前の確認に使う探し方は、副方式の探し方と区別するため記録しない）。
    var logsLookups = true
    private(set) var lookupCount = 0
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
        lookupCount += 1
        if logsLookups {
            log.record(.lookUpGoToField)
        }
        if let suspension {
            await suspension.suspend()
        }
        if let error {
            throw error
        }
        try simulateAXScan(clock: clock, log: log, taking: lookupLatency, cutoff: cutoff)
        guard let field else { return nil }
        return GoToFieldControls(field: field, goButton: goButton, suggestionList: suggestionList)
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
