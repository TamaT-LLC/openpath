import Testing

import OpenPathCore

/// 外へ伝えるイベント（確定・閉じる）を、そのキーを離すまで預かる状態機械（Issue #90、#100）。
/// 時刻はテストから手動で進める Clock（`TestClock`）で決める。
@Suite("PaletteEventKeyHold: 確定・閉じるのキーを離すまで預かる")
struct PaletteEventKeyHoldTests {
    private static let confirm = HeldKey.returnKey.event
    private static let returnKeyCode = KeyStroke.returnKey.keyCode
    private static let justBeforeLimit = PaletteEventKeyHold.maximumHold - .milliseconds(1)

    private let clock = TestClock()

    private func makeHold() -> PaletteEventKeyHold {
        PaletteEventKeyHold(clock: clock)
    }

    /// keyDown でイベントが出て、預けた直後の状態。
    private func holding(_ event: PaletteEvent, keyCode: UInt16) -> PaletteEventKeyHold {
        var hold = makeHold()
        hold.receive(event, onKeyDownOf: keyCode)
        return hold
    }

    private func holding(_ heldKey: HeldKey) -> PaletteEventKeyHold {
        holding(heldKey.event, keyCode: heldKey.key.keyCode)
    }

    // MARK: - 預ける・離す

    @Test("確定（Enter）も閉じる（Esc）も、keyDown では外へ伝えず、キーを離すまで預かる", arguments: HeldKey.all)
    func eventIsHeldUntilKeyUp(heldKey: HeldKey) {
        var hold = makeHold()

        hold.receive(heldKey.event, onKeyDownOf: heldKey.key.keyCode)

        #expect(hold.isHolding)
    }

    @Test("そのキーを離したら、預かったイベントを 1 回だけ返す", arguments: HeldKey.all)
    func keyUpReleasesEventOnce(heldKey: HeldKey) {
        var hold = holding(heldKey)
        clock.advance(by: .milliseconds(120))

        let first = hold.keyUp(keyCode: heldKey.key.keyCode)
        let second = hold.keyUp(keyCode: heldKey.key.keyCode)

        #expect(first == .send(heldKey.event))
        #expect(second == .unrelated)
        #expect(!hold.isHolding)
    }

    @Test(
        "Cmd+Enter・テンキーの Enter も、keyDown の時点の内容（パスと Cmd の有無）で離したときに返す",
        arguments: [
            (KeyStroke.returnKey, true),
            (KeyStroke.keypadEnter, false),
            (KeyStroke.keypadEnter, true),
        ]
    )
    func confirmKeepsContentsDecidedOnKeyDown(key: KeyStroke, openImmediately: Bool) {
        let event = PaletteEvent.confirm(path: "/Users/example/repos/fern", openImmediately: openImmediately)
        var hold = holding(event, keyCode: key.keyCode)

        let release = hold.keyUp(keyCode: key.keyCode)

        #expect(release == .send(event))
    }

    @Test("ほかのキーを離しても伝えず、預かったままにする", arguments: HeldKey.withOtherKeys)
    func otherKeyUpDoesNotRelease(heldKey: HeldKey, otherKey: KeyStroke) {
        var hold = holding(heldKey)

        let otherRelease = hold.keyUp(keyCode: otherKey.keyCode)
        let isStillHolding = hold.isHolding
        let release = hold.keyUp(keyCode: heldKey.key.keyCode)

        #expect(otherRelease == .unrelated)
        #expect(isStillHolding)
        #expect(release == .send(heldKey.event))
    }

    @Test("何も預かっていなければ、キーを離しても何も返さない", arguments: HeldKey.all)
    func keyUpWithoutHoldIsUnrelated(heldKey: HeldKey) {
        var hold = makeHold()

        let release = hold.keyUp(keyCode: heldKey.key.keyCode)

        #expect(release == .unrelated)
    }

    // MARK: - 預かっている間のキー

    @Test(
        "預かっている間は、パレットのキー・文字入力・リピートをすべて消費する（背後のパネルへも検索フィールドへも渡さない）",
        arguments: HeldKey.all, KeyChord.paletteChords + KeyChord.textInputChords
    )
    func everyKeyDownIsDiscardedWhileHolding(heldKey: HeldKey, chord: KeyChord) {
        var hold = holding(heldKey)
        clock.advance(by: Self.justBeforeLimit)

        let resolutions = [chord.input(), chord.input(isRepeat: true)].map { hold.resolve($0) }

        #expect(resolutions == [.discard, .discard])
    }

    @Test("預かっていなければ、キーの扱いは PaletteKeyBinding と同じ", arguments: KeyChord.paletteChords + KeyChord.textInputChords)
    func resolveFollowsKeyBindingWhenNotHolding(chord: KeyChord) {
        var hold = makeHold()
        let inputs = [chord.input(), chord.input(isRepeat: true), chord.input(hasMarkedText: true), chord.input(isLocked: true)]

        let resolutions = inputs.map { hold.resolve($0) }

        #expect(resolutions == inputs.map(PaletteKeyBinding.resolve))
    }

    // MARK: - 上限

    @Test("上限の直前に離せば伝える", arguments: HeldKey.all)
    func keyUpJustBeforeLimitReleases(heldKey: HeldKey) {
        var hold = holding(heldKey)
        clock.advance(by: Self.justBeforeLimit)

        let isHolding = hold.isHolding
        let release = hold.keyUp(keyCode: heldKey.key.keyCode)

        #expect(isHolding)
        #expect(release == .send(heldKey.event))
    }

    @Test("上限に達したら取り消す。離しても伝えず、取り消したことを 1 回だけ返す", arguments: HeldKey.all)
    func holdExpiresAtLimit(heldKey: HeldKey) {
        var hold = holding(heldKey)
        clock.advance(by: PaletteEventKeyHold.maximumHold)

        let isHolding = hold.isHolding
        let first = hold.keyUp(keyCode: heldKey.key.keyCode)
        let second = hold.keyUp(keyCode: heldKey.key.keyCode)

        #expect(!isHolding)
        #expect(first == .expired(heldKey.event))
        #expect(second == .unrelated)
    }

    @Test(
        "上限を過ぎ、リピートも来ていなければ、キーの扱いは PaletteKeyBinding に戻る（そのキーのリピートは従来どおり消費し、↓ は選択を動かす）",
        arguments: HeldKey.all
    )
    func keysFollowKeyBindingAfterExpiry(heldKey: HeldKey) {
        var hold = holding(heldKey)
        clock.advance(by: max(PaletteEventKeyHold.maximumHold, PaletteEventKeyHold.repeatTimeout))

        let heldKeyRepeat = hold.resolve(heldKey.key.input(isRepeat: true))
        // 直前のリピートで押し続けているとみなされないよう、リピートの途切れを待ってから↓を押す
        clock.advance(by: PaletteEventKeyHold.repeatTimeout)
        let downArrow = hold.resolve(KeyStroke.downArrow.input())

        #expect(heldKeyRepeat == .discard)
        #expect(downArrow == .perform(.moveSelection(by: 1)))
    }

    @Test("上限を過ぎた後に押し直したキーは、新しいイベントとして預かる", arguments: HeldKey.all)
    func newEventAfterExpiryIsHeldAgain(heldKey: HeldKey) {
        var hold = holding(heldKey)
        clock.advance(by: PaletteEventKeyHold.maximumHold)
        let retried = heldKey.retriedEvent

        hold.receive(retried, onKeyDownOf: heldKey.key.keyCode)
        clock.advance(by: Self.justBeforeLimit)
        let isHolding = hold.isHolding
        let release = hold.keyUp(keyCode: heldKey.key.keyCode)

        #expect(isHolding)
        #expect(release == .send(retried))
    }

    @Test("上限は指定でき、生成時ではなく keyDown の時刻から測る")
    func limitIsMeasuredFromKeyDown() {
        let limit: Duration = .milliseconds(500)
        clock.advance(by: .seconds(10))
        var hold = PaletteEventKeyHold(clock: clock, maximumHold: limit)
        clock.advance(by: .seconds(5))
        hold.receive(Self.confirm, onKeyDownOf: Self.returnKeyCode)

        clock.advance(by: limit - .milliseconds(1))
        let isHoldingBeforeLimit = hold.isHolding
        clock.advance(by: .milliseconds(1))
        let isHoldingAtLimit = hold.isHolding
        let release = hold.keyUp(keyCode: Self.returnKeyCode)

        #expect(isHoldingBeforeLimit)
        #expect(!isHoldingAtLimit)
        #expect(release == .expired(Self.confirm))
    }

    // MARK: - 上限で取り消した後も押し続けている場合

    @Test(
        "上限で取り消した後も、そのキーのリピートが続いている間はキー入力をすべて捨てる（ほかのキーで閉じたり確定したりすると、残りのリピートが背後のパネルへ届くため）",
        arguments: HeldKey.withOtherKeys
    )
    func keysStayOwnedWhileRepeatContinuesAfterExpiry(heldKey: HeldKey, otherKey: KeyStroke) {
        var hold = holding(heldKey)
        let resolutionsWhileHeld = repeating(heldKey.key, on: &hold, until: PaletteEventKeyHold.maximumHold + .milliseconds(500))
        let otherKeyWhileHeld = hold.resolve(otherKey.input())

        let release = hold.keyUp(keyCode: heldKey.key.keyCode)
        let otherKeyAfterRelease = hold.resolve(otherKey.input())

        #expect(resolutionsWhileHeld.allSatisfy { $0 == .discard })
        #expect(otherKeyWhileHeld == .discard)
        #expect(release == .expired(heldKey.event))
        #expect(otherKeyAfterRelease == PaletteKeyBinding.resolve(otherKey.input()))
    }

    @Test("上限で取り消した後、リピートが途切れたら（keyUp を取りこぼした）キーの扱いを PaletteKeyBinding に戻す", arguments: HeldKey.all)
    func keysAreReleasedWhenRepeatStopsAfterExpiry(heldKey: HeldKey) {
        var hold = holding(heldKey)
        _ = repeating(heldKey.key, on: &hold, until: PaletteEventKeyHold.maximumHold + .milliseconds(200))

        clock.advance(by: PaletteEventKeyHold.repeatTimeout - .milliseconds(1))
        let downArrowBeforeTimeout = hold.resolve(KeyStroke.downArrow.input())
        clock.advance(by: PaletteEventKeyHold.repeatTimeout)
        let downArrowAfterTimeout = hold.resolve(KeyStroke.downArrow.input())

        #expect(downArrowBeforeTimeout == .discard)
        #expect(downArrowAfterTimeout == .perform(.moveSelection(by: 1)))
    }

    @Test(
        "上限で取り消した後に同じキーを押し直したら（前の keyUp を取りこぼした）、新しい操作として扱う",
        arguments: HeldKey.all, [false, true]
    )
    func pressingSameKeyAgainAfterExpiryStartsNewEvent(heldKey: HeldKey, isRepeating: Bool) {
        var hold = holding(heldKey)
        if isRepeating {
            _ = repeating(heldKey.key, on: &hold, until: PaletteEventKeyHold.maximumHold + .milliseconds(200))
        } else {
            clock.advance(by: PaletteEventKeyHold.maximumHold)
        }
        let retried = heldKey.retriedEvent

        let resolution = hold.resolve(heldKey.key.input())
        hold.receive(retried, onKeyDownOf: heldKey.key.keyCode)
        let isHolding = hold.isHolding
        let release = hold.keyUp(keyCode: heldKey.key.keyCode)

        #expect(resolution == .perform(heldKey.action))
        #expect(isHolding)
        #expect(release == .send(retried))
    }

    /// キーのリピート（50ms 間隔）を、keyDown からの経過時間が `until` に達するまで渡す。
    private func repeating(_ key: KeyStroke, on hold: inout PaletteEventKeyHold, until end: Duration) -> [PaletteKeyResolution] {
        let interval: Duration = .milliseconds(50)
        var elapsed: Duration = .zero
        var resolutions: [PaletteKeyResolution] = []
        while elapsed < end {
            clock.advance(by: interval)
            elapsed += interval
            resolutions.append(hold.resolve(key.input(isRepeat: true)))
        }
        return resolutions
    }

    // MARK: - 取り消し

    @Test("パレットがキーでなくなったら取り消し、取り消したイベントを返す。その後に離しても伝えない", arguments: HeldKey.all)
    func cancelDropsHeldEvent(heldKey: HeldKey) {
        var hold = holding(heldKey)

        let canceled = hold.cancel()
        let release = hold.keyUp(keyCode: heldKey.key.keyCode)

        #expect(canceled == heldKey.event)
        #expect(!hold.isHolding)
        #expect(release == .unrelated)
    }

    @Test("預かっていないイベント・上限を過ぎたイベントの取り消しは、取り消したイベントとして返さない", arguments: HeldKey.all)
    func cancelWithoutActiveHoldReturnsNil(heldKey: HeldKey) {
        var idle = makeHold()
        var expired = holding(heldKey)
        clock.advance(by: PaletteEventKeyHold.maximumHold)

        let canceledIdle = idle.cancel()
        let canceledExpired = expired.cancel()
        let releaseAfterCancel = expired.keyUp(keyCode: heldKey.key.keyCode)

        #expect(canceledIdle == nil)
        #expect(canceledExpired == nil)
        #expect(releaseAfterCancel == .unrelated)
    }
}

/// 離すまで預かるキーと、そのキーの操作・外へ伝えるイベント。
struct HeldKey: Sendable, CustomTestStringConvertible {
    let key: KeyStroke
    let action: PaletteAction
    let event: PaletteEvent
    /// 同じキーを押し直したときのイベント。確定は別の候補で押し直した場合を表す
    let retriedEvent: PaletteEvent

    var testDescription: String { key.testDescription }

    static let returnKey = HeldKey(
        key: .returnKey,
        action: .confirm(openImmediately: false),
        event: .confirm(path: "/Users/example/Library", openImmediately: false),
        retriedEvent: .confirm(path: "/Users/example/repos/fern", openImmediately: false)
    )
    static let escape = HeldKey(key: .escape, action: .dismiss, event: .dismiss, retriedEvent: .dismiss)

    static let all: [HeldKey] = [.returnKey, .escape]

    /// 預かっているキーと、それとは別のキーの組
    static let withOtherKeys: [(HeldKey, KeyStroke)] = all.flatMap { heldKey in
        [KeyStroke.returnKey, .escape, .keypadEnter, .tab, .downArrow, .a]
            .filter { $0.keyCode != heldKey.key.keyCode }
            .map { (heldKey, $0) }
    }
}
