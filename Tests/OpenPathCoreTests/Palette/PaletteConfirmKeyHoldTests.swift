import Testing

import OpenPathCore

/// 確定のキー（Enter）を離すまで確定を預かる状態機械（Issue #90）。
/// 時刻はテストから手動で進める Clock（`TestClock`）で決める。
@Suite("PaletteConfirmKeyHold: 確定のキーを離すまで預かる")
struct PaletteConfirmKeyHoldTests {
    private static let confirm = PaletteEvent.confirm(path: "/Users/example/Library", openImmediately: false)
    private static let returnKeyCode = KeyStroke.returnKey.keyCode
    private static let justBeforeLimit = PaletteConfirmKeyHold.maximumHold - .milliseconds(1)

    private let clock = TestClock()

    private func makeHold() -> PaletteConfirmKeyHold {
        PaletteConfirmKeyHold(clock: clock)
    }

    /// keyDown で確定が出て、預けた直後の状態。
    private func holdingConfirm(_ event: PaletteEvent = confirm, keyCode: UInt16 = returnKeyCode) -> PaletteConfirmKeyHold {
        var hold = makeHold()
        let immediate = hold.receive(event, onKeyDownOf: keyCode)
        #expect(immediate == nil)
        return hold
    }

    // MARK: - 預ける・離す

    @Test("確定は keyDown では外へ伝えず、キーを離すまで預かる")
    func confirmIsHeldUntilKeyUp() {
        var hold = makeHold()

        let immediate = hold.receive(Self.confirm, onKeyDownOf: Self.returnKeyCode)

        #expect(immediate == nil)
        #expect(hold.isHolding)
    }

    @Test("確定のキーを離したら、預かった確定を 1 回だけ返す")
    func keyUpReleasesConfirmOnce() {
        var hold = holdingConfirm()
        clock.advance(by: .milliseconds(120))

        let first = hold.keyUp(keyCode: Self.returnKeyCode)
        let second = hold.keyUp(keyCode: Self.returnKeyCode)

        #expect(first == .confirm(Self.confirm))
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
        var hold = holdingConfirm(event, keyCode: key.keyCode)

        let release = hold.keyUp(keyCode: key.keyCode)

        #expect(release == .confirm(event))
    }

    @Test("閉じる（Esc）は預からず、keyDown ですぐ外へ伝える")
    func dismissIsSentImmediately() {
        var hold = makeHold()

        let immediate = hold.receive(.dismiss, onKeyDownOf: KeyStroke.escape.keyCode)
        let release = hold.keyUp(keyCode: KeyStroke.escape.keyCode)

        #expect(immediate == .dismiss)
        #expect(release == .unrelated)
        #expect(!hold.isHolding)
    }

    @Test("ほかのキーを離しても確定せず、預かったままにする", arguments: [KeyStroke.escape, .keypadEnter, .downArrow, .a])
    func otherKeyUpDoesNotRelease(otherKey: KeyStroke) {
        var hold = holdingConfirm()

        let otherRelease = hold.keyUp(keyCode: otherKey.keyCode)
        let isStillHolding = hold.isHolding
        let release = hold.keyUp(keyCode: Self.returnKeyCode)

        #expect(otherRelease == .unrelated)
        #expect(isStillHolding)
        #expect(release == .confirm(Self.confirm))
    }

    @Test("何も預かっていなければ、キーを離しても何も返さない")
    func keyUpWithoutHoldIsUnrelated() {
        var hold = makeHold()

        let release = hold.keyUp(keyCode: Self.returnKeyCode)

        #expect(release == .unrelated)
    }

    // MARK: - 預かっている間のキー

    @Test(
        "預かっている間は、パレットのキー・文字入力・リピートをすべて消費する（背後のパネルへも検索フィールドへも渡さない）",
        arguments: KeyChord.paletteChords + KeyChord.textInputChords
    )
    func everyKeyDownIsDiscardedWhileHolding(chord: KeyChord) {
        let hold = holdingConfirm()
        clock.advance(by: Self.justBeforeLimit)

        #expect(hold.resolve(chord.input()) == .discard)
        #expect(hold.resolve(chord.input(isRepeat: true)) == .discard)
    }

    @Test("預かっていなければ、キーの扱いは PaletteKeyBinding と同じ", arguments: KeyChord.paletteChords + KeyChord.textInputChords)
    func resolveFollowsKeyBindingWhenNotHolding(chord: KeyChord) {
        let hold = makeHold()
        let inputs = [chord.input(), chord.input(isRepeat: true), chord.input(hasMarkedText: true), chord.input(isLocked: true)]

        for input in inputs {
            #expect(hold.resolve(input) == PaletteKeyBinding.resolve(input))
        }
    }

    // MARK: - 上限

    @Test("上限の直前に離せば確定する")
    func keyUpJustBeforeLimitReleases() {
        var hold = holdingConfirm()
        clock.advance(by: Self.justBeforeLimit)

        let isHolding = hold.isHolding
        let release = hold.keyUp(keyCode: Self.returnKeyCode)

        #expect(isHolding)
        #expect(release == .confirm(Self.confirm))
    }

    @Test("上限に達したら確定を取り消す。離しても確定せず、取り消したことを 1 回だけ返す")
    func holdExpiresAtLimit() {
        var hold = holdingConfirm()
        clock.advance(by: PaletteConfirmKeyHold.maximumHold)

        let isHolding = hold.isHolding
        let first = hold.keyUp(keyCode: Self.returnKeyCode)
        let second = hold.keyUp(keyCode: Self.returnKeyCode)

        #expect(!isHolding)
        #expect(first == .expired)
        #expect(second == .unrelated)
    }

    @Test("上限を過ぎたらキーの扱いは PaletteKeyBinding に戻る（Enter のリピートは従来どおり消費し、↓ は選択を動かす）")
    func keysFollowKeyBindingAfterExpiry() {
        let hold = holdingConfirm()
        clock.advance(by: PaletteConfirmKeyHold.maximumHold)

        #expect(hold.resolve(KeyStroke.returnKey.input(isRepeat: true)) == .discard)
        #expect(hold.resolve(KeyStroke.downArrow.input()) == .perform(.moveSelection(by: 1)))
    }

    @Test("上限を過ぎた後に押し直した Enter は、新しい確定として預かる")
    func newConfirmAfterExpiryIsHeldAgain() {
        var hold = holdingConfirm()
        clock.advance(by: PaletteConfirmKeyHold.maximumHold)
        let retried = PaletteEvent.confirm(path: "/Users/example/repos/fern", openImmediately: false)

        let immediate = hold.receive(retried, onKeyDownOf: Self.returnKeyCode)
        clock.advance(by: Self.justBeforeLimit)
        let isHolding = hold.isHolding
        let release = hold.keyUp(keyCode: Self.returnKeyCode)

        #expect(immediate == nil)
        #expect(isHolding)
        #expect(release == .confirm(retried))
    }

    @Test("上限は指定でき、生成時ではなく keyDown の時刻から測る")
    func limitIsMeasuredFromKeyDown() {
        let limit: Duration = .milliseconds(500)
        clock.advance(by: .seconds(10))
        var hold = PaletteConfirmKeyHold(clock: clock, maximumHold: limit)
        clock.advance(by: .seconds(5))
        _ = hold.receive(Self.confirm, onKeyDownOf: Self.returnKeyCode)

        clock.advance(by: limit - .milliseconds(1))
        let isHoldingBeforeLimit = hold.isHolding
        clock.advance(by: .milliseconds(1))
        let isHoldingAtLimit = hold.isHolding
        let release = hold.keyUp(keyCode: Self.returnKeyCode)

        #expect(isHoldingBeforeLimit)
        #expect(!isHoldingAtLimit)
        #expect(release == .expired)
    }

    // MARK: - 取り消し

    @Test("パレットがキーでなくなったら取り消し、その後に離しても確定しない")
    func cancelDropsHeldConfirm() {
        var hold = holdingConfirm()

        let didCancel = hold.cancel()
        let release = hold.keyUp(keyCode: Self.returnKeyCode)

        #expect(didCancel)
        #expect(!hold.isHolding)
        #expect(release == .unrelated)
    }

    @Test("預かっていない確定・上限を過ぎた確定の取り消しは、取り消した確定として数えない")
    func cancelWithoutActiveHoldReturnsFalse() {
        var idle = makeHold()
        var expired = holdingConfirm()
        clock.advance(by: PaletteConfirmKeyHold.maximumHold)

        let didCancelIdle = idle.cancel()
        let didCancelExpired = expired.cancel()
        let releaseAfterCancel = expired.keyUp(keyCode: Self.returnKeyCode)

        #expect(!didCancelIdle)
        #expect(!didCancelExpired)
        #expect(releaseAfterCancel == .unrelated)
    }
}
