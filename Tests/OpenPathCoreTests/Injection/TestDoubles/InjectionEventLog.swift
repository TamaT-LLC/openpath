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
