/// パレットのキー操作で扱う macOS の仮想キーコード（`NSEvent.keyCode`）。
///
/// 値は Carbon の `kVK_*` と同じ。Core は Carbon を import しないため必要な分だけを持ち、
/// 一致はテストで Carbon の定数と突き合わせる。
/// 仮想キーコードはキーボード上の物理位置を表すため、文字キーは US 配列での位置になる。
public enum PaletteKeyCode: UInt16, CaseIterable, Sendable {
    case `return` = 0x24
    case keypadEnter = 0x4C
    case tab = 0x30
    case escape = 0x35
    case upArrow = 0x7E
    case downArrow = 0x7D

    // 文字キー。入力される文字でショートカットを判定できない配列（キリル文字等）での代わりに使う
    case ansiA = 0x00
    case ansiC = 0x08
    case ansiN = 0x2D
    case ansiP = 0x23
    case ansiV = 0x09
    case ansiX = 0x07
    case ansiZ = 0x06

    /// 文字キーの US 配列での文字（小文字）。特殊キーは nil
    public var ansiLetter: Character? {
        switch self {
        case .ansiA: "a"
        case .ansiC: "c"
        case .ansiN: "n"
        case .ansiP: "p"
        case .ansiV: "v"
        case .ansiX: "x"
        case .ansiZ: "z"
        case .return, .keypadEnter, .tab, .escape, .upArrow, .downArrow: nil
        }
    }
}
