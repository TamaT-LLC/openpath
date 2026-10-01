/// 確定のキー（Enter / Cmd+Enter / テンキーの Enter）を離すまで、確定を外（AppCoordinator）へ伝えずに預かる
/// （UX-001 §4、Issue #90）。
///
/// 確定を外へ伝えると注入が始まり、パレットはキー入力を NSOpenPanel へ返す（`PaletteWindowControlling.releaseKey()`）。
/// Enter を押したままだと、その後のリピートが NSOpenPanel に届き、既定ボタン「開く」が押されてしまう。
/// キーを手放した後のイベントはパレットのローカルイベントモニタからは見えないため、捨てようがない。
/// そこで、確定の内容（パスと Cmd の有無）は keyDown の時点で決めるが、外へ伝えるのはそのキーを離した（keyUp）ときにする。
/// 離すまでの間はパレットがキーのままなので、リピートはすべてパレットで消費できる。
///
/// - 預かっている間は、パレット宛ての keyDown をすべて消費する（`resolve(_:)`）。リピートのほか、
///   Esc で閉じて残りのリピートが背後のパネルへ届くことや、確定した後に検索語・選択が変わることを防ぐ。
/// - 上限（`maximumHold`）までに離さなければ確定を取り消す。keyUp を取りこぼしたときに、パレットが入力を
///   受け付けないままにならないため。取り消した後もパレットはキーのままで、残りのリピートは
///   `PaletteKeyBinding` が従来どおり消費する（背後のパネルへは届かない）。
/// - パレットがキーでなくなったら（パネルの消滅で隠れた、パネルをクリックした等）`cancel()` で取り消す。
///   そのキーの keyUp はパレットに届かないうえ、別のパネルの表示に切り替わった後に確定を伝えないため。
///
/// 時刻は注入した Clock で測る。上限はタイマーを使わず、次のキー入力（`resolve` / `keyUp`）や `isHolding` を
/// 読んだ時点で判定する。預かっている状態はキー入力の扱いにしか影響しないため、それで足りる。
public struct PaletteConfirmKeyHold: Sendable {
    /// 確定のキーを押してから離すまでを待つ上限。
    /// Issue #90 の再現手順（keyDown → 0.5 秒後から 50ms 間隔で 20 回のリピート → keyUp。約 1.5 秒）や、
    /// 実機 QA の物理キーの約 2 秒の長押しでも、離したときに確定できる長さにする。
    /// これより長く押し続けるのは確定の操作ではないとみなす（UX-001 §1「誤爆防止」）。
    public static let maximumHold: Duration = .seconds(3)

    /// 預かっている確定。
    private struct Hold: Sendable {
        let event: PaletteEvent
        let keyCode: UInt16
        /// 生成からの経過時間で表した上限の時刻
        let deadline: Duration
    }

    private let maximumHold: Duration
    /// 生成からの経過時間。`any Clock<Duration>` の Instant は存在型のままでは比較できないため、経過時間に置き換える
    private let elapsed: @Sendable () -> Duration
    /// 預かっている確定。上限を過ぎても、keyUp・取り消し・次の確定まで「上限を過ぎた」ことの報告のために残す
    private var hold: Hold?

    /// - Parameters:
    ///   - clock: 上限の判定に使う。テストでは手動で進める Clock を渡す。
    ///   - maximumHold: 確定のキーを離すまでを待つ上限。
    public init<C: Clock<Duration>>(clock: C, maximumHold: Duration = Self.maximumHold) {
        let origin = clock.now
        elapsed = { origin.duration(to: clock.now) }
        self.maximumHold = maximumHold
    }

    /// 確定を預かっていて、上限に達していないか。
    public var isHolding: Bool {
        guard let hold else { return false }
        return !isExpired(hold)
    }

    /// keyDown の扱いを決める。確定を預かっている間はすべて消費し、それ以外は `PaletteKeyBinding` に任せる。
    public func resolve(_ input: PaletteKeyInput) -> PaletteKeyResolution {
        isHolding ? .discard : PaletteKeyBinding.resolve(input)
    }

    /// keyDown の操作で出たパレットのイベントを渡す。
    /// - Returns: 今すぐ外へ伝えるイベント。確定はそのキーを離すまで預かって nil を返し、閉じる（Esc）はそのまま返す。
    public mutating func receive(_ event: PaletteEvent, onKeyDownOf keyCode: UInt16) -> PaletteEvent? {
        guard case .confirm = event else { return event }
        hold = Hold(event: event, keyCode: keyCode, deadline: elapsed() + maximumHold)
        return nil
    }

    /// keyUp を受けたときに呼ぶ。
    public mutating func keyUp(keyCode: UInt16) -> PaletteConfirmKeyRelease {
        guard let hold, hold.keyCode == keyCode else { return .unrelated }
        self.hold = nil
        return isExpired(hold) ? .expired : .confirm(hold.event)
    }

    /// 預かっている確定を取り消す（パレットがキーでなくなったとき）。
    /// - Returns: 上限に達していない確定を取り消したか。
    @discardableResult
    public mutating func cancel() -> Bool {
        defer { hold = nil }
        return isHolding
    }

    private func isExpired(_ hold: Hold) -> Bool {
        elapsed() >= hold.deadline
    }
}

/// 確定のキーを離したときの結果。
public enum PaletteConfirmKeyRelease: Equatable, Sendable {
    /// 預かっていた確定のキーを上限までに離した。この確定を外へ伝える
    case confirm(PaletteEvent)
    /// 預かっていた確定のキーを、上限を過ぎてから離した。確定は取り消し済み
    case expired
    /// 預かっていたキーではない（または何も預かっていない）
    case unrelated
}
