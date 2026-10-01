import Testing

import OpenPathCore

/// 確定・閉じるのキーを離すまで預かる処理の診断（実機 QA の PAL-08・S-08 を debug ログで判定するため）。
/// 預けた・離して伝えた・取り消したことを、押していた時間と捨てたキーの数とともに報告する。確定のパスは報告しない。
@Suite("PaletteEventKeyHold: 診断の報告")
struct PaletteEventKeyHoldDiagnosticTests {
    private static let path = "/Users/example/Library"
    private static let confirm = PaletteEvent.confirm(path: path, openImmediately: false)
    /// Issue #90・#100 の再現手順: keyDown の 0.5 秒後から、50ms 間隔で 20 回のリピート、最後に keyUp
    private static let initialRepeatDelay: Duration = .milliseconds(500)
    private static let repeatInterval: Duration = .milliseconds(50)
    private static let repeatCount = 20

    private let clock = TestClock()
    private let recorder = DiagnosticRecorder<PaletteEventKeyHoldDiagnostic>()

    private func makeHold() -> PaletteEventKeyHold {
        let recorder = recorder
        return PaletteEventKeyHold(clock: clock) { recorder.record($0) }
    }

    /// `key` を押して `event` を預け、0.5 秒後から 50ms 間隔で `count` 回のリピートを渡す。
    private func pressAndRepeat(
        _ key: KeyStroke,
        event: PaletteEvent,
        on hold: inout PaletteEventKeyHold,
        count: Int = repeatCount
    ) {
        _ = hold.resolve(key.input())
        hold.receive(event, onKeyDownOf: key.keyCode)
        clock.advance(by: Self.initialRepeatDelay)
        for _ in 0..<count {
            _ = hold.resolve(key.input(isRepeat: true))
            clock.advance(by: Self.repeatInterval)
        }
    }

    private static func record(
        _ event: PaletteKeyHoldRecord.Event,
        key: KeyStroke,
        held: Duration = .zero,
        isLimitReached: Bool = false,
        repeats: Int = 0,
        otherKeys: Int = 0
    ) -> PaletteKeyHoldRecord {
        PaletteKeyHoldRecord(
            event: event,
            keyCode: key.keyCode,
            heldDuration: held,
            isLimitReached: isLimitReached,
            discardedRepeatCount: repeats,
            discardedOtherKeyCount: otherKeys
        )
    }

    // MARK: - 預ける・離す

    @Test(
        "預けたときに、イベントの種類・キー・Cmd の有無を報告する（確定のパスは報告しない）",
        arguments: [
            (KeyStroke.returnKey, PaletteEvent.confirm(path: path, openImmediately: false), PaletteKeyHoldRecord.Event.confirm(openImmediately: false)),
            (KeyStroke.returnKey, .confirm(path: path, openImmediately: true), .confirm(openImmediately: true)),
            (KeyStroke.keypadEnter, .confirm(path: path, openImmediately: false), .confirm(openImmediately: false)),
            (KeyStroke.escape, .dismiss, .dismiss),
        ]
    )
    func reportsStartOnReceive(key: KeyStroke, event: PaletteEvent, expected: PaletteKeyHoldRecord.Event) {
        var hold = makeHold()

        hold.receive(event, onKeyDownOf: key.keyCode)

        #expect(recorder.diagnostics == [.started(Self.record(expected, key: key))])
    }

    @Test("Issue #90 の手順で離したら、伝えたことを、押していた時間と捨てたリピートの数とともに報告する")
    func reportsSentWithHeldDurationAndDiscardedRepeats() {
        var hold = makeHold()
        pressAndRepeat(.returnKey, event: Self.confirm, on: &hold)

        let release = hold.keyUp(keyCode: KeyStroke.returnKey.keyCode)

        #expect(release == .send(Self.confirm))
        #expect(recorder.diagnostics.last == .ended(
            Self.record(.confirm(openImmediately: false), key: .returnKey, held: .milliseconds(1500), repeats: Self.repeatCount),
            .sent
        ))
        #expect(recorder.diagnostics.count == 2)
    }

    @Test("Esc の長押しも、離したときに伝えたことと捨てたリピートの数を報告する（Issue #100）")
    func reportsSentForEscape() {
        var hold = makeHold()
        pressAndRepeat(.escape, event: .dismiss, on: &hold)

        _ = hold.keyUp(keyCode: KeyStroke.escape.keyCode)

        #expect(recorder.diagnostics.last == .ended(
            Self.record(.dismiss, key: .escape, held: .milliseconds(1500), repeats: Self.repeatCount),
            .sent
        ))
    }

    @Test("預かっている間に捨てたほかのキーは、リピートとは分けて数える")
    func countsOtherKeysSeparately() {
        var hold = makeHold()
        hold.receive(Self.confirm, onKeyDownOf: KeyStroke.returnKey.keyCode)
        clock.advance(by: .milliseconds(200))
        _ = hold.resolve(KeyStroke.escape.input())
        _ = hold.resolve(KeyStroke.returnKey.input(isRepeat: true))
        _ = hold.resolve(KeyStroke.downArrow.input())
        clock.advance(by: .milliseconds(100))

        _ = hold.keyUp(keyCode: KeyStroke.returnKey.keyCode)

        #expect(recorder.diagnostics.last == .ended(
            Self.record(.confirm(openImmediately: false), key: .returnKey, held: .milliseconds(300), repeats: 1, otherKeys: 2),
            .sent
        ))
    }

    // MARK: - 取り消し

    @Test("上限を過ぎてから離したら、取り消したこと（expired）を、上限の後に捨てたリピートも含めて報告する")
    func reportsExpiredOnKeyUpAfterLimit() {
        var hold = makeHold()
        // 0.5 秒 + 50ms × 60 回 = 3.5 秒押し続ける
        pressAndRepeat(.returnKey, event: Self.confirm, on: &hold, count: 60)

        let release = hold.keyUp(keyCode: KeyStroke.returnKey.keyCode)

        #expect(release == .expired(Self.confirm))
        #expect(recorder.diagnostics.last == .ended(
            Self.record(.confirm(openImmediately: false), key: .returnKey, held: .milliseconds(3500), isLimitReached: true, repeats: 60),
            .expired
        ))
    }

    @Test(
        "パレットがキーでなくなったら、取り消したこと（canceled）と上限に達していたかを報告する",
        arguments: [(Duration.milliseconds(800), false), (PaletteEventKeyHold.maximumHold, true)]
    )
    func reportsCanceled(after elapsed: Duration, isLimitReached: Bool) {
        var hold = makeHold()
        hold.receive(.dismiss, onKeyDownOf: KeyStroke.escape.keyCode)
        clock.advance(by: elapsed)

        hold.cancel()

        #expect(recorder.diagnostics.last == .ended(
            Self.record(.dismiss, key: .escape, held: elapsed, isLimitReached: isLimitReached),
            .canceled
        ))
    }

    @Test("上限の後に同じキーを押し直したら（前の keyUp を取りこぼした）、前の確定を repressed で報告してから、新しく預けたことを報告する")
    func reportsRepressedThenStart() {
        var hold = makeHold()
        hold.receive(Self.confirm, onKeyDownOf: KeyStroke.returnKey.keyCode)
        clock.advance(by: PaletteEventKeyHold.maximumHold)

        let resolution = hold.resolve(KeyStroke.returnKey.input())
        hold.receive(.confirm(path: Self.path, openImmediately: true), onKeyDownOf: KeyStroke.returnKey.keyCode)

        #expect(resolution == .perform(.confirm(openImmediately: false)))
        #expect(recorder.diagnostics == [
            .started(Self.record(.confirm(openImmediately: false), key: .returnKey)),
            .ended(
                Self.record(.confirm(openImmediately: false), key: .returnKey, held: PaletteEventKeyHold.maximumHold, isLimitReached: true),
                .repressed
            ),
            .started(Self.record(.confirm(openImmediately: true), key: .returnKey)),
        ])
    }

    @Test("上限の後にリピートが途切れ、別のキーで新しく預けたら、前のイベントを replaced で報告する")
    func reportsReplacedWhenNewEventIsHeld() {
        var hold = makeHold()
        hold.receive(Self.confirm, onKeyDownOf: KeyStroke.returnKey.keyCode)
        let elapsed = PaletteEventKeyHold.maximumHold + PaletteEventKeyHold.repeatTimeout
        clock.advance(by: elapsed)

        let resolution = hold.resolve(KeyStroke.escape.input())
        hold.receive(.dismiss, onKeyDownOf: KeyStroke.escape.keyCode)

        #expect(resolution == .perform(.dismiss))
        #expect(recorder.diagnostics.suffix(2) == [
            .ended(Self.record(.confirm(openImmediately: false), key: .returnKey, held: elapsed, isLimitReached: true), .replaced),
            .started(Self.record(.dismiss, key: .escape)),
        ])
    }

    @Test("預かっていない間のキー・関係のない keyUp・預かっていない取り消しでは、何も報告しない")
    func reportsNothingWithoutHold() {
        var hold = makeHold()

        _ = hold.resolve(KeyStroke.downArrow.input())
        _ = hold.resolve(KeyStroke.a.input())
        _ = hold.keyUp(keyCode: KeyStroke.returnKey.keyCode)
        hold.cancel()
        hold.receive(Self.confirm, onKeyDownOf: KeyStroke.returnKey.keyCode)
        _ = hold.keyUp(keyCode: KeyStroke.a.keyCode)

        #expect(recorder.diagnostics == [.started(Self.record(.confirm(openImmediately: false), key: .returnKey))])
    }

    // MARK: - ログの文言

    @Test(
        "預けたときの文言",
        arguments: [
            (PaletteKeyHoldRecord.Event.confirm(openImmediately: false), KeyStroke.returnKey, "palette key hold started (event: confirm, key: return, cmd: false)"),
            (.confirm(openImmediately: true), .keypadEnter, "palette key hold started (event: confirm, key: keypadEnter, cmd: true)"),
            (.dismiss, .escape, "palette key hold started (event: dismiss, key: escape)"),
            (.confirm(openImmediately: false), .a, "palette key hold started (event: confirm, key: 0, cmd: false)"),
        ]
    )
    func startMessage(event: PaletteKeyHoldRecord.Event, key: KeyStroke, expected: String) {
        #expect(PaletteEventKeyHoldDiagnostic.started(Self.record(event, key: key)).logMessage == expected)
    }

    @Test("手放したときの文言には、結果・押していた時間・上限に達したか・捨てたキーの数を含める")
    func endMessage() {
        let record = Self.record(.confirm(openImmediately: false), key: .returnKey, held: .milliseconds(1534), repeats: 20, otherKeys: 1)

        #expect(PaletteEventKeyHoldDiagnostic.ended(record, .sent).logMessage
            == "palette key hold ended (event: confirm, key: return, cmd: false, outcome: sent, held: 1534ms, "
            + "limitReached: false, discardedRepeats: 20, discardedOtherKeys: 1)")
        #expect(PaletteEventKeyHoldDiagnostic.ended(Self.record(.dismiss, key: .escape, held: .seconds(3), isLimitReached: true), .expired)
            .logMessage
            == "palette key hold ended (event: dismiss, key: escape, outcome: expired, held: 3000ms, "
            + "limitReached: true, discardedRepeats: 0, discardedOtherKeys: 0)")
    }

    @Test("どの結果の文言も、パスとログを読むスクリプトの目印を含まない", arguments: PaletteKeyHoldEnd.allCases)
    func messagesAreSafe(end: PaletteKeyHoldEnd) {
        var hold = makeHold()
        pressAndRepeat(.returnKey, event: Self.confirm, on: &hold, count: 3)
        hold.cancel()
        let record = Self.record(.confirm(openImmediately: true), key: .returnKey, held: .milliseconds(10))
        let messages = recorder.diagnostics.map(\.logMessage) + [PaletteEventKeyHoldDiagnostic.ended(record, end).logMessage]

        #expect(messages.allSatisfy(DiagnosticLogContract.isSafe))
        #expect(messages.allSatisfy { !$0.contains("Library") })
    }
}
