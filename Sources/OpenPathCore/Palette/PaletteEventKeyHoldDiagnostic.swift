/// 確定・閉じるのキーを離すまで預かる処理（`PaletteEventKeyHold`）の診断。debug ログに出す。
///
/// 実機 QA（PAL-08・S-08）で、キーを離した時刻と注入の開始（`coordinator injection start`）・パレットを閉じた時刻
/// （`palette hidden`）の順序と間隔、長押し中に捨てたキーの数、上限での取り消しを、ログの行で判定するためのもの。
/// 確定のパス（`PaletteEvent.confirm` の path）は持たない。
public enum PaletteEventKeyHoldDiagnostic: Equatable, Sendable {
    /// keyDown で出たイベントを預かった
    case started(PaletteKeyHoldRecord)
    /// 預かっていたイベントを手放した（外へ伝えた、または取り消した）
    case ended(PaletteKeyHoldRecord, PaletteKeyHoldEnd)

    /// debug ログの文言。例:
    /// - `palette key hold started (event: confirm, key: return, cmd: false)`
    /// - `palette key hold ended (event: confirm, key: return, cmd: false, outcome: sent, held: 1534ms, limitReached: false, discardedRepeats: 20, discardedOtherKeys: 0)`
    public var logMessage: String {
        switch self {
        case .started(let record):
            return "palette key hold started (\(record.keyFields.joined(separator: ", ")))"
        case .ended(let record, let end):
            let fields = record.keyFields + [
                "outcome: \(end.rawValue)",
                "held: \(InjectionLogFormat.milliseconds(record.heldDuration))",
                "limitReached: \(record.isLimitReached)",
                "discardedRepeats: \(record.discardedRepeatCount)",
                "discardedOtherKeys: \(record.discardedOtherKeyCount)",
            ]
            return "palette key hold ended (\(fields.joined(separator: ", ")))"
        }
    }

    /// 既定の報告先。debug ログに出す（リリースビルドの既定の info では出さない）。
    public static func log(_ diagnostic: PaletteEventKeyHoldDiagnostic) {
        Log.debug(diagnostic.logMessage)
    }
}

/// 預かったイベントの、報告の時点の状態。
public struct PaletteKeyHoldRecord: Equatable, Sendable {
    /// 預かったイベントの種類。確定のパスは持たない
    public enum Event: Equatable, Sendable {
        /// 確定。openImmediately は Cmd+Enter
        case confirm(openImmediately: Bool)
        /// Esc でパレットを閉じる
        case dismiss

        init(_ event: PaletteEvent) {
            switch event {
            case .confirm(_, let openImmediately):
                self = .confirm(openImmediately: openImmediately)
            case .dismiss:
                self = .dismiss
            }
        }
    }

    public let event: Event
    /// 押したキーの仮想キーコード
    public let keyCode: UInt16
    /// 預けた（keyDown の）時点からの経過時間
    public let heldDuration: Duration
    /// 上限（`PaletteEventKeyHold.maximumHold`）に達していたか
    public let isLimitReached: Bool
    /// 預かっている間に捨てた、そのキーの keyDown（リピート）の数
    public let discardedRepeatCount: Int
    /// 預かっている間に捨てた、ほかのキーの keyDown の数
    public let discardedOtherKeyCount: Int

    public init(
        event: Event,
        keyCode: UInt16,
        heldDuration: Duration,
        isLimitReached: Bool,
        discardedRepeatCount: Int,
        discardedOtherKeyCount: Int
    ) {
        self.event = event
        self.keyCode = keyCode
        self.heldDuration = heldDuration
        self.isLimitReached = isLimitReached
        self.discardedRepeatCount = discardedRepeatCount
        self.discardedOtherKeyCount = discardedOtherKeyCount
    }

    /// イベントの種類・キー・Cmd の有無（確定のときだけ）
    fileprivate var keyFields: [String] {
        switch event {
        case .confirm(let openImmediately):
            ["event: confirm", "key: \(Self.keyName(keyCode))", "cmd: \(openImmediately)"]
        case .dismiss:
            ["event: dismiss", "key: \(Self.keyName(keyCode))"]
        }
    }

    /// 確定・閉じるのキーは名前で、それ以外は仮想キーコードの数値で表す
    private static func keyName(_ keyCode: UInt16) -> String {
        if keyCode == PaletteKeyBinding.keypadEnterKeyCode {
            return "keypadEnter"
        }
        switch VirtualKey(rawValue: UInt32(keyCode)) {
        case .return:
            return "return"
        case .escape:
            return "escape"
        default:
            return "\(keyCode)"
        }
    }
}

/// 預かっていたイベントを手放した理由。
public enum PaletteKeyHoldEnd: String, CaseIterable, Equatable, Sendable {
    /// 上限までにそのキーを離し、イベントを外へ伝えた（確定なら注入が始まり、閉じるならパレットを閉じる）
    case sent
    /// 上限を過ぎてからそのキーを離した。イベントは伝えない
    case expired
    /// キーを離す前にパレットがキーでなくなった。イベントは伝えない
    case canceled
    /// 上限の後に同じキーを押し直した（前の keyUp を取りこぼした）。イベントは伝えず、押し直しを新しい操作として扱う
    case repressed
    /// 上限の後にリピートが途切れ、別のイベントを預かった（前の keyUp を取りこぼした）。イベントは伝えない
    case replaced
}
