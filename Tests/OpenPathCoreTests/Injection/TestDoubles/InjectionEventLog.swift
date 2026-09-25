import OpenPathCore

/// 注入の手順で起きた操作を、仮想時刻付きで発生順に記録する。
@MainActor
final class InjectionEventLog {
    enum Event: Equatable {
        /// シート出現判定の基準を記録した
        case makeProbe
        case prepareForKeyEvents
        case key(InjectionKeyStroke)
        case sheetCheck(isShown: Bool)
        /// AX の走査を打ち切り条件で途中でやめた
        case scanCutOff
        /// ペーストボードへの書き込み（パスの書き込みと、元の内容への復元）
        case pasteboardWrite(PasteboardSnapshot)
        case didSubmitGoToSheet(autoConfirm: Bool)
        /// 注入先を記録した
        case captureTarget
        /// 注入先がまだ有効か確かめた（TargetGuardFake.logsChecks のときだけ記録する）
        case targetCheck
        /// 副方式: 移動先シートの入力欄を探した
        case lookUpGoToField
        /// auto_confirm: 「開く」ボタンを探した
        case lookUpOpenButton
        /// パネル内の要素に kAXValue をセットした
        case setValue(element: String, value: String)
        /// パネル内の要素を AXPress した
        case press(element: String)
        /// パネル内の要素に kAXConfirmAction を送った
        case confirmField(element: String)
        /// パネル内の要素の kAXFocused に true をセットした（キー入力の受け先にした）
        case focusField(element: String)
    }

    struct Entry: Equatable {
        let time: Duration
        let event: Event
    }

    private let clock: VirtualClock
    private(set) var entries: [Entry] = []

    init(clock: VirtualClock) {
        self.clock = clock
    }

    var events: [Event] {
        entries.map(\.event)
    }

    /// 送られたキー操作だけを発生順に返す。
    var keyStrokes: [InjectionKeyStroke] {
        events.compactMap { event in
            guard case .key(let keyStroke) = event else { return nil }
            return keyStroke
        }
    }

    func record(_ event: Event) {
        entries.append(Entry(time: clock.elapsed, event: event))
    }
}

/// フェイクから投げる、InjectionError 以外の失敗。
struct AdapterFailure: Error, Equatable {}
