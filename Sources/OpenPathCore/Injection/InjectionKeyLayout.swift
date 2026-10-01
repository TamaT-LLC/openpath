/// キー操作に付ける修飾キー。Core に CoreGraphics・Carbon を持ち込まないため、OpenPathMac 側で CGEventFlags 等に写す。
public struct InjectionKeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = InjectionKeyModifiers(rawValue: 1 << 0)
    public static let shift = InjectionKeyModifiers(rawValue: 1 << 1)
}

/// キー操作を、どの文字のキーをどの修飾キーで押すかで表したもの（Issue #68）。
public struct InjectionKeySpec: Equatable, Sendable {
    /// 押すキーが入力する文字（修飾キーのうち Shift を除いて押したとき）。入力ソースのキー配列から仮想キーコードを求めるのに使う。
    /// nil は文字に依らないキー（Return）で、`physicalKeyCode` をそのまま使う。
    public let character: String?
    /// QWERTY（ANSI）配列での物理位置の仮想キーコード（kVK_ANSI_G 等）。キー配列から求められないときに使う。
    public let physicalKeyCode: UInt16
    public let modifiers: InjectionKeyModifiers
    /// 文字が Shift なしのキーに無いとき、Shift 付きのキーも探すか（/ が Shift+7 の配列など）。
    /// ショートカット（⌘A 等）は Shift を足すと別のショートカットになるため探さない。
    public let allowsShiftedCharacter: Bool

    public init(character: String?, physicalKeyCode: UInt16, modifiers: InjectionKeyModifiers, allowsShiftedCharacter: Bool = false) {
        self.character = character
        self.physicalKeyCode = physicalKeyCode
        self.modifiers = modifiers
        self.allowsShiftedCharacter = allowsShiftedCharacter
    }
}

extension InjectionKeyStroke {
    /// 物理位置の仮想キーコード（HIToolbox の kVK_ANSI_G 等と同じ値。Core に Carbon を持ち込まないため数値で持つ）。
    enum PhysicalKeyCode {
        static let ansiA: UInt16 = 0x00
        static let ansiG: UInt16 = 0x05
        static let ansiV: UInt16 = 0x09
        static let returnKey: UInt16 = 0x24
        static let ansiSlash: UInt16 = 0x2C
    }

    /// ログに出す名前。
    public var logName: String {
        switch self {
        case .goToFolder: "⌘⇧G"
        case .selectAll: "⌘A"
        case .paste: "⌘V"
        case .returnKey: "Return"
        case .slash: "/"
        }
    }

    /// どの文字のキーをどの修飾キーで押すか。
    public var spec: InjectionKeySpec {
        switch self {
        case .goToFolder:
            InjectionKeySpec(character: "g", physicalKeyCode: PhysicalKeyCode.ansiG, modifiers: [.command, .shift])
        case .selectAll:
            InjectionKeySpec(character: "a", physicalKeyCode: PhysicalKeyCode.ansiA, modifiers: .command)
        case .paste:
            InjectionKeySpec(character: "v", physicalKeyCode: PhysicalKeyCode.ansiV, modifiers: .command)
        case .returnKey:
            InjectionKeySpec(character: nil, physicalKeyCode: PhysicalKeyCode.returnKey, modifiers: [])
        case .slash:
            InjectionKeySpec(character: "/", physicalKeyCode: PhysicalKeyCode.ansiSlash, modifiers: [], allowsShiftedCharacter: true)
        }
    }
}

/// 送るキー（仮想キーコードと修飾キー）と、その求め方。
public struct InjectionResolvedKey: Equatable, Sendable {
    /// 仮想キーコードの求め方。
    public enum Source: String, Equatable, Sendable {
        /// 入力ソースのキー配列から求めた
        case layout
        /// キー配列を読めない・文字のキーが無いため、QWERTY の物理位置を使った（従来の送り方）
        case physicalPosition
        /// 文字に依らないキー（Return）
        case fixed
    }

    public let keyCode: UInt16
    public let modifiers: InjectionKeyModifiers
    public let source: Source

    public init(keyCode: UInt16, modifiers: InjectionKeyModifiers, source: Source) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.source = source
    }
}

/// 入力ソースのキー配列から、キー操作の文字を入力する仮想キーコードを求める（Issue #68）。
///
/// 仮想キーコードは物理キーの位置を表すため、Dvorak などでは kVK_ANSI_G を押しても「g」にならず、⌘⇧G が別のショートカットになる。
/// そこで、キー配列（UCKeyTranslate）で各キーが入力する文字を調べ、目的の文字を入力するキーを選ぶ。
public enum InjectionKeyCodeResolver {
    /// キー配列の 1 キーの文字。仮想キーコードと修飾キーを受け取り、そのキーで入力される文字を返す。読めなければ nil。
    public typealias Translate = (_ keyCode: UInt16, _ modifiers: InjectionKeyModifiers) -> String?

    /// 文字を探すキー（ANSI・ISO・JIS の文字キー）の仮想キーコード。テンキーは、テンキーとして扱うアプリがあるため使わない。
    /// 0x00〜0x32 は文字キーと Return・Tab・Space（文字が一致しないため選ばれない）、0x5D / 0x5E は JIS の ¥ と _。
    static let characterKeyCodes: [UInt16] = Array(0x00...0x32) + [0x5D, 0x5E]

    /// - Parameter translate: 現在の入力ソースのキー配列。nil はキー配列を読めないことを表す（物理位置で送る）。
    /// - Returns: 目的の文字を入力するキー。次の順で探す。どれでもなければ物理位置（従来の送り方）。
    ///   1. 物理位置のキー（US / JIS など、従来どおりで済む配列では変えない）
    ///   2. 文字キーを仮想キーコードの順に
    ///   3. `allowsShiftedCharacter` なら、1・2 を Shift 付きで
    ///   文字は、修飾キーのうち Shift を除いたもの（ショートカットなら ⌘）を押したときのキー配列で引く。
    ///   「Dvorak - QWERTY ⌘」のように ⌘ の間だけ配列が変わるキー配列でも、アプリがショートカットとして受け取る文字で選ぶため。
    public static func resolve(_ spec: InjectionKeySpec, translate: Translate?) -> InjectionResolvedKey {
        guard let character = spec.character else {
            return InjectionResolvedKey(keyCode: spec.physicalKeyCode, modifiers: spec.modifiers, source: .fixed)
        }
        let physical = InjectionResolvedKey(keyCode: spec.physicalKeyCode, modifiers: spec.modifiers, source: .physicalPosition)
        guard let translate else { return physical }
        let lookupModifiers = spec.modifiers.subtracting(.shift)
        let candidates = [spec.physicalKeyCode] + characterKeyCodes.filter { $0 != spec.physicalKeyCode }
        if let keyCode = candidates.first(where: { translate($0, lookupModifiers) == character }) {
            return InjectionResolvedKey(keyCode: keyCode, modifiers: spec.modifiers, source: .layout)
        }
        guard spec.allowsShiftedCharacter else { return physical }
        let shiftedModifiers = lookupModifiers.union(.shift)
        if let keyCode = candidates.first(where: { translate($0, shiftedModifiers) == character }) {
            return InjectionResolvedKey(keyCode: keyCode, modifiers: spec.modifiers.union(.shift), source: .layout)
        }
        return physical
    }
}
