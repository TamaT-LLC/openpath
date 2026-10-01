import Testing

import OpenPathCore

/// キー処理（PaletteKeyController）と同じ順に、PaletteEventKeyHold・PaletteViewModel を通した場合の振る舞い。
@MainActor
@Suite("PaletteEventKeyHold: Enter の長押し（Issue #90）")
struct PaletteEventKeyHoldScenarioTests {
    /// Issue #90 の再現手順: keyDown の 0.5 秒後から、50ms 間隔で 20 回のリピート、最後に keyUp
    private static let initialRepeatDelay: Duration = .milliseconds(500)
    private static let repeatInterval: Duration = .milliseconds(50)
    private static let repeatCount = 20

    private let keys = PaletteKeySequence()

    @Test("keyDown → 0.5 秒後から 50ms 間隔で 20 回のリピート → keyUp: リピートはすべてパレットで消費し、離したときに 1 回だけ確定する")
    func issue90RepeatSequence() {
        keys.keyDown(KeyStroke.returnKey.input())
        keys.clock.advance(by: Self.initialRepeatDelay)
        for _ in 0..<Self.repeatCount {
            keys.keyDown(KeyStroke.returnKey.input(isRepeat: true))
            keys.clock.advance(by: Self.repeatInterval)
        }
        let sentBeforeKeyUp = keys.sentEvents
        keys.keyUp(.returnKey)

        #expect(sentBeforeKeyUp.isEmpty)
        #expect(keys.sentEvents == [PaletteKeySequence.confirm])
        #expect(keys.passedKeys.isEmpty)
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
        keys.clock.advance(by: Self.initialRepeatDelay)
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
    }

    @Test("上限を超えて押し続けた後に Esc を押しても閉じず、離した後の Esc で閉じる")
    func escapeAfterLimitWhileStillHoldingIsIgnored() {
        keys.keyDown(KeyStroke.returnKey.input())
        keys.clock.advance(by: Self.initialRepeatDelay)
        var elapsed = Self.initialRepeatDelay
        while elapsed < PaletteEventKeyHold.maximumHold + .milliseconds(500) {
            keys.keyDown(KeyStroke.returnKey.input(isRepeat: true))
            keys.clock.advance(by: Self.repeatInterval)
            elapsed += Self.repeatInterval
        }
        keys.keyDown(KeyStroke.escape.input())
        keys.keyDown(KeyStroke.returnKey.input(isRepeat: true))
        let sentWhileHeld = keys.sentEvents
        keys.keyUp(.returnKey)
        keys.keyUp(.escape)
        keys.keyDown(KeyStroke.escape.input())

        #expect(sentWhileHeld.isEmpty)
        #expect(keys.sentEvents == [.dismiss])
        #expect(keys.passedKeys.isEmpty)
    }

    @Test("Esc は従来どおり keyDown で閉じる")
    func escapeDismissesOnKeyDown() {
        keys.keyDown(KeyStroke.escape.input())

        #expect(keys.sentEvents == [.dismiss])
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

/// PaletteKeyController と同じ順にキー入力を通し、外へ伝えたイベントと、パレットで消費しなかったキーを記録する。
@MainActor
private final class PaletteKeySequence {
    static let path = "/Users/example/Library"
    static let confirm = PaletteEvent.confirm(path: path, openImmediately: false)

    let clock = TestClock()
    let viewModel = PaletteViewModel(homeDirectory: "/Users/example")
    private(set) var hold: PaletteEventKeyHold
    /// 外（AppCoordinator）へ伝えたイベント。伝えると注入が始まり、パレットはキーを手放す
    private(set) var sentEvents: [PaletteEvent] = []
    /// パレットで消費せずに渡したキー。パレットがキーを手放す前は検索フィールドへ、手放した後は背後のパネルへ届く
    private(set) var passedKeys: [PaletteKeyInput] = []

    init() {
        hold = PaletteEventKeyHold(clock: clock)
        viewModel.replaceRows([PaletteRow(name: "Library", path: Self.path, lastUsed: nil)])
    }

    /// PaletteKeyController の keyDown の処理と同じ順に通す。
    func keyDown(_ input: PaletteKeyInput) {
        switch hold.resolve(input) {
        case .passThrough:
            passedKeys.append(input)
        case .discard, .edit:
            break
        case .perform(let action):
            guard let event = viewModel.perform(action) else { return }
            if let immediate = hold.receive(event, onKeyDownOf: input.keyCode) {
                sentEvents.append(immediate)
            }
        }
    }

    /// PaletteKeyController の keyUp の処理と同じ順に通す。
    func keyUp(_ key: KeyStroke) {
        if case .send(let event) = hold.keyUp(keyCode: key.keyCode) {
            sentEvents.append(event)
        }
    }
}
