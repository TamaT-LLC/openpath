import Testing

import OpenPathCore

/// キー処理（PaletteKeyController）と同じ順に、PaletteEventKeyHold・PaletteViewModel を通した場合の振る舞い。
@MainActor
@Suite("PaletteEventKeyHold: Enter の長押し（Issue #90）")
struct PaletteEventKeyHoldScenarioTests {
    private let keys = PaletteKeySequence()

    @Test("keyDown → 0.5 秒後から 50ms 間隔で 20 回のリピート → keyUp: リピートはすべてパレットで消費し、離したときに 1 回だけ確定する")
    func issue90RepeatSequence() {
        keys.pressAndRepeat(.returnKey)
        let sentBeforeKeyUp = keys.sentEvents
        keys.keyUp(.returnKey)

        #expect(sentBeforeKeyUp.isEmpty)
        #expect(keys.sentEvents == [PaletteKeySequence.confirm])
        #expect(keys.passedKeys.isEmpty)
        #expect(keys.keysReachingPanel.isEmpty)
    }

    @Test("単発の Enter は、離したときに確定する")
    func singlePress() {
        keys.keyDown(KeyStroke.returnKey.input())
        let sentBeforeKeyUp = keys.sentEvents
        keys.clock.advance(by: .milliseconds(90))
        keys.keyUp(.returnKey)

        #expect(sentBeforeKeyUp.isEmpty)
        #expect(keys.sentEvents == [PaletteKeySequence.confirm])
    }

    @Test("Cmd+Enter は、離したときに「開く」まで押す確定として伝える")
    func commandReturn() {
        keys.keyDown(KeyStroke.returnKey.input(.command))
        keys.keyDown(KeyStroke.returnKey.input(.command, isRepeat: true))
        keys.keyUp(.returnKey)

        #expect(keys.sentEvents == [.confirm(path: PaletteKeySequence.path, openImmediately: true)])
    }

    @Test("長押しの間に Esc を押しても閉じない（閉じると残りのリピートが背後のパネルへ届くため）")
    func escapeWhileHoldingIsIgnored() {
        keys.keyDown(KeyStroke.returnKey.input())
        keys.clock.advance(by: PaletteKeySequence.initialRepeatDelay)
        keys.keyDown(KeyStroke.escape.input())
        keys.keyDown(KeyStroke.returnKey.input(isRepeat: true))
        keys.keyUp(.escape)
        keys.keyUp(.returnKey)

        #expect(keys.sentEvents == [PaletteKeySequence.confirm])
    }

    @Test("上限を超えて押し続けたら確定せず、その後のリピートもパレットで消費する")
    func holdingPastLimitConfirmsNothing() {
        keys.keyDown(KeyStroke.returnKey.input())
        keys.clock.advance(by: PaletteEventKeyHold.maximumHold)
        keys.keyDown(KeyStroke.returnKey.input(isRepeat: true))
        keys.keyDown(KeyStroke.returnKey.input(isRepeat: true))
        keys.keyUp(.returnKey)

        #expect(keys.sentEvents.isEmpty)
        #expect(keys.passedKeys.isEmpty)
        #expect(keys.keysReachingPanel.isEmpty)
    }

    @Test("上限を超えて押し続けた後に Esc を押しても閉じず、離した後の Esc で閉じる")
    func escapeAfterLimitWhileStillHoldingIsIgnored() {
        keys.pressAndRepeat(.returnKey, until: PaletteEventKeyHold.maximumHold + .milliseconds(500))
        keys.keyDown(KeyStroke.escape.input())
        keys.keyDown(KeyStroke.returnKey.input(isRepeat: true))
        let sentWhileHeld = keys.sentEvents
        keys.keyUp(.returnKey)
        keys.keyUp(.escape)
        keys.keyDown(KeyStroke.escape.input())
        keys.keyUp(.escape)

        #expect(sentWhileHeld.isEmpty)
        #expect(keys.sentEvents == [.dismiss])
        #expect(keys.passedKeys.isEmpty)
        #expect(keys.keysReachingPanel.isEmpty)
    }

    @Test("IME の変換中の Enter は IME に渡し、確定を預からない")
    func returnWhileComposingGoesToInputMethod() {
        keys.keyDown(KeyStroke.returnKey.input(hasMarkedText: true))
        let isHolding = keys.hold.isHolding
        keys.keyUp(.returnKey)

        #expect(!isHolding)
        #expect(keys.sentEvents.isEmpty)
        #expect(keys.passedKeys.count == 1)
    }

    @Test("↑↓ のリピートは預からずに選択を動かし続ける")
    func arrowRepeatsKeepMoving() {
        keys.viewModel.replaceRows(["a", "b", "c", "d"].map { PaletteRow(name: $0, path: "/tmp/\($0)", lastUsed: nil) })

        keys.keyDown(KeyStroke.downArrow.input())
        keys.keyDown(KeyStroke.downArrow.input(isRepeat: true))
        keys.keyDown(KeyStroke.downArrow.input(isRepeat: true))

        #expect(keys.viewModel.selectedIndex == 3)
        #expect(keys.sentEvents.isEmpty)
        #expect(!keys.hold.isHolding)
    }
}

/// Esc も Enter と同じく、離すまで閉じる操作を預かる（Issue #100）。
@MainActor
@Suite("PaletteEventKeyHold: Esc の長押し（Issue #100）")
struct PaletteEscapeKeyHoldScenarioTests {
    private let keys = PaletteKeySequence()

    @Test("keyDown → 0.5 秒後から 50ms 間隔で 20 回のリピート → keyUp: リピートはすべてパレットで消費し、離したときに 1 回だけ閉じる（背後のパネルの「キャンセル」に届かない）")
    func issue100RepeatSequence() {
        keys.pressAndRepeat(.escape)
        let sentBeforeKeyUp = keys.sentEvents
        keys.keyUp(.escape)

        #expect(sentBeforeKeyUp.isEmpty)
        #expect(keys.sentEvents == [.dismiss])
        #expect(keys.passedKeys.isEmpty)
        #expect(keys.keysReachingPanel.isEmpty)
    }

    @Test("単発の Esc は、離したときにパレットだけを閉じる")
    func singlePress() {
        keys.keyDown(KeyStroke.escape.input())
        let sentBeforeKeyUp = keys.sentEvents
        keys.clock.advance(by: .milliseconds(90))
        keys.keyUp(.escape)

        #expect(sentBeforeKeyUp.isEmpty)
        #expect(keys.sentEvents == [.dismiss])
        #expect(keys.keysReachingPanel.isEmpty)
    }

    @Test("上限を超えて押し続けたら閉じず、その後のリピートもパレットで消費する。離した後に押し直した Esc では閉じる")
    func holdingPastLimitDismissesNothing() {
        keys.pressAndRepeat(.escape, until: PaletteEventKeyHold.maximumHold + .milliseconds(500))
        keys.keyUp(.escape)
        let sentAfterLongPress = keys.sentEvents
        keys.keyDown(KeyStroke.escape.input())
        keys.keyUp(.escape)

        #expect(sentAfterLongPress.isEmpty)
        #expect(keys.sentEvents == [.dismiss])
        #expect(keys.passedKeys.isEmpty)
        #expect(keys.keysReachingPanel.isEmpty)
    }

    @Test("押している間にパレットがキーでなくなったら閉じる操作を取り消し、キーが戻った後に離しても閉じない")
    func losingKeyWhileHoldingCancels() {
        keys.keyDown(KeyStroke.escape.input())
        keys.clock.advance(by: PaletteKeySequence.initialRepeatDelay)
        keys.resignKey()
        keys.becomeKey()
        keys.keyUp(.escape)
        let sentAfterRelease = keys.sentEvents
        keys.keyDown(KeyStroke.escape.input())
        keys.keyUp(.escape)

        #expect(sentAfterRelease.isEmpty)
        #expect(keys.sentEvents == [.dismiss])
    }

    @Test("長押しの間に Enter を押しても確定しない（確定すると残りの Esc のリピートが背後のパネルへ届くため）")
    func returnWhileHoldingIsIgnored() {
        keys.keyDown(KeyStroke.escape.input())
        keys.clock.advance(by: PaletteKeySequence.initialRepeatDelay)
        keys.keyDown(KeyStroke.returnKey.input())
        keys.keyDown(KeyStroke.escape.input(isRepeat: true))
        keys.keyUp(.returnKey)
        keys.keyUp(.escape)

        #expect(keys.sentEvents == [.dismiss])
        #expect(keys.keysReachingPanel.isEmpty)
    }

    @Test("IME の変換中の Esc は IME に渡し、閉じる操作を預からない")
    func escapeWhileComposingGoesToInputMethod() {
        keys.keyDown(KeyStroke.escape.input(hasMarkedText: true))
        let isHolding = keys.hold.isHolding
        keys.keyUp(.escape)

        #expect(!isHolding)
        #expect(keys.sentEvents.isEmpty)
        #expect(keys.passedKeys.count == 1)
    }

    @Test("注入中（ロック中）の Esc は従来どおり捨て、閉じる操作を預からない")
    func escapeWhileLockedIsDiscarded() {
        keys.keyDown(KeyStroke.escape.input(isLocked: true))
        let isHolding = keys.hold.isHolding
        keys.keyUp(.escape)

        #expect(!isHolding)
        #expect(keys.sentEvents.isEmpty)
        #expect(keys.passedKeys.isEmpty)
    }
}

/// PaletteKeyController と同じ順にキー入力を通し、外へ伝えたイベントと、パレットで消費しなかったキーを記録する。
@MainActor
private final class PaletteKeySequence {
    static let path = "/Users/example/Library"
    static let confirm = PaletteEvent.confirm(path: path, openImmediately: false)
    /// Issue #90・#100 の再現手順: keyDown の 0.5 秒後から、50ms 間隔で 20 回のリピート、最後に keyUp
    static let initialRepeatDelay: Duration = .milliseconds(500)
    static let repeatInterval: Duration = .milliseconds(50)
    static let repeatCount = 20

    let clock = TestClock()
    let viewModel = PaletteViewModel(homeDirectory: "/Users/example")
    private(set) var hold: PaletteEventKeyHold
    /// 外（AppCoordinator）へ伝えたイベント
    private(set) var sentEvents: [PaletteEvent] = []
    /// パレットで消費せずに検索フィールド（と IME）へ渡したキー
    private(set) var passedKeys: [PaletteKeyInput] = []
    /// パレットがキーを手放した後の keyDown。背後のパネルへ届き、Enter なら「開く」、Esc なら「キャンセル」が押される
    private(set) var keysReachingPanel: [PaletteKeyInput] = []
    /// パレットがキーウィンドウか
    private var isPaletteKey = true

    init() {
        hold = PaletteEventKeyHold(clock: clock)
        viewModel.replaceRows([PaletteRow(name: "Library", path: Self.path, lastUsed: nil)])
    }

    /// PaletteKeyController の keyDown の処理と同じ順に通す。
    func keyDown(_ input: PaletteKeyInput) {
        guard isPaletteKey else {
            keysReachingPanel.append(input)
            return
        }
        switch hold.resolve(input) {
        case .passThrough:
            passedKeys.append(input)
        case .discard, .edit:
            break
        case .perform(let action):
            // 確定・閉じるは、そのキーを離すまで預かる
            guard let event = viewModel.perform(action) else { return }
            hold.receive(event, onKeyDownOf: input.keyCode)
        }
    }

    /// PaletteKeyController の keyUp の処理と同じ順に通す。
    func keyUp(_ key: KeyStroke) {
        guard isPaletteKey else { return }
        if case .send(let event) = hold.keyUp(keyCode: key.keyCode) {
            // 伝えると、確定なら注入が始まり、閉じるならパレットが隠れて、どちらもパレットはキーを手放す
            sentEvents.append(event)
            isPaletteKey = false
        }
    }

    /// keyDown の 0.5 秒後から 50ms 間隔でリピートを送り、keyDown からの経過時間が `end` に達するまで押し続ける。
    /// 既定は Issue #90・#100 の再現手順の 20 回。keyUp は呼び出し側で送る。
    func pressAndRepeat(
        _ key: KeyStroke,
        until end: Duration = initialRepeatDelay + repeatInterval * repeatCount
    ) {
        keyDown(key.input())
        clock.advance(by: Self.initialRepeatDelay)
        var elapsed = Self.initialRepeatDelay
        while elapsed < end {
            keyDown(key.input(isRepeat: true))
            clock.advance(by: Self.repeatInterval)
            elapsed += Self.repeatInterval
        }
    }

    /// パネルをクリックした等で、パレットがキーでなくなった（PaletteKeyController の didResignKeyNotification）。
    func resignKey() {
        isPaletteKey = false
        hold.cancel()
    }

    /// パレットをクリックして、パレットがまたキーになった。
    func becomeKey() {
        isPaletteKey = true
    }
}
