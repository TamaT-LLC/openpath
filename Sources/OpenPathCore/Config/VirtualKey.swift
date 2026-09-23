/// ホットキーに指定できる macOS の仮想キー。`rawValue` は Carbon の `kVK_*` と同じ仮想キーコード。
///
/// OpenPathCore は Carbon を import しない方針のため、設定で使う範囲だけを純データとして持つ。
/// 値が Carbon と一致することはテスト側で Carbon の定数と突き合わせて検証する。
/// 仮想キーコードはキーボード上の物理位置を表すため、文字キーは ANSI 配列での位置になる。
public enum VirtualKey: UInt32, CaseIterable, Sendable {
    // 文字キー（kVK_ANSI_A 〜 kVK_ANSI_Z）
    case a = 0x00
    case s = 0x01
    case d = 0x02
    case f = 0x03
    case h = 0x04
    case g = 0x05
    case z = 0x06
    case x = 0x07
    case c = 0x08
    case v = 0x09
    case b = 0x0B
    case q = 0x0C
    case w = 0x0D
    case e = 0x0E
    case r = 0x0F
    case y = 0x10
    case t = 0x11
    case o = 0x1F
    case u = 0x20
    case i = 0x22
    case p = 0x23
    case l = 0x25
    case j = 0x26
    case k = 0x28
    case n = 0x2D
    case m = 0x2E

    // 数字キー（kVK_ANSI_0 〜 kVK_ANSI_9）
    case digit1 = 0x12
    case digit2 = 0x13
    case digit3 = 0x14
    case digit4 = 0x15
    case digit6 = 0x16
    case digit5 = 0x17
    case digit9 = 0x19
    case digit7 = 0x1A
    case digit8 = 0x1C
    case digit0 = 0x1D

    // 記号キー
    case equal = 0x18
    case minus = 0x1B
    case rightBracket = 0x1E
    case leftBracket = 0x21
    case quote = 0x27
    case semicolon = 0x29
    case backslash = 0x2A
    case comma = 0x2B
    case slash = 0x2C
    case period = 0x2F
    case grave = 0x32

    // 特殊キー
    case `return` = 0x24
    case tab = 0x30
    case space = 0x31
    /// Backspace に相当するキー（kVK_Delete）
    case delete = 0x33
    case escape = 0x35
    case leftArrow = 0x7B
    case rightArrow = 0x7C
    case downArrow = 0x7D
    case upArrow = 0x7E

    // ファンクションキー
    case f5 = 0x60
    case f6 = 0x61
    case f7 = 0x62
    case f3 = 0x63
    case f8 = 0x64
    case f9 = 0x65
    case f11 = 0x67
    case f10 = 0x6D
    case f12 = 0x6F
    case f4 = 0x76
    case f2 = 0x78
    case f1 = 0x7A
}

public extension VirtualKey {
    /// 名前（大文字小文字は区別しない）からキーを引く。未知の名前なら nil
    init?(name: String) {
        guard let key = Self.keysByName[name.lowercased()] else { return nil }
        self = key
    }
}

extension VirtualKey {
    /// すべてのキー名からキーへの対応。名前の一意性はテストで保証するため、重複時は先勝ちにしてクラッシュを避ける
    private static let keysByName: [String: VirtualKey] = Dictionary(
        allCases.flatMap { key in key.names.map { name in (name, key) } },
        uniquingKeysWith: { first, _ in first }
    )
}
