/// 外（AppCoordinator）へ伝えるパレットのイベント（確定・閉じる）を、そのキーを離すまで預かる
/// （UX-001 §4、Issue #90・#100）。
///
/// イベントを外へ伝えると、パレットはキー入力を NSOpenPanel へ返す。確定なら注入が始まって
/// `PaletteWindowControlling.releaseKey()` で、閉じる（Esc）ならパレットが隠れて手放す。
/// キーを押したままだと、その後のリピートが NSOpenPanel に届き、Enter なら既定ボタン「開く」が、
/// Esc なら「キャンセル」が押されてしまう。キーを手放した後のイベントはパレットのローカルイベントモニタからは
/// 見えないため、捨てようがない。
/// そこで、イベントの内容（確定のパスと Cmd の有無）は keyDown の時点で決めるが、外へ伝えるのはそのキーを
/// 離した（keyUp）ときにする。離すまでの間はパレットがキーのままなので、リピートはすべてパレットで消費できる。
///
/// - 預かっている間は、パレット宛ての keyDown をすべて消費する（`resolve(_:)`）。リピートのほか、
///   別のキー（Enter の長押し中の Esc、Esc の長押し中の Enter）で閉じたり確定したりして、残りのリピートが
///   背後のパネルへ届くことや、確定した後に検索語・選択が変わることを防ぐ。
/// - 上限（`maximumHold`）までに離さなければイベントを取り消す。keyUp を取りこぼしたときに、パレットが入力を
///   受け付けないままにならないため。
/// - 取り消した後も、そのキーのリピートが続いている間（最後の keyDown から `repeatTimeout` 未満）は、
///   押し続けているとみなして keyDown をすべて消費し続ける。上限を過ぎてから別のキーで閉じたり確定したりすると、
///   残りのリピートが背後のパネルへ届いてしまうため。リピートが途切れたら（keyUp を取りこぼした）、
///   同じキーを押し直したら、またはそのキーを離したら、キーの扱いを `PaletteKeyBinding` に戻す。
/// - パレットがキーでなくなったら（パネルの消滅で隠れた、パネルをクリックした等）`cancel()` で取り消す。
///   そのキーの keyUp はパレットに届かないうえ、別のパネルの表示に切り替わった後にイベントを伝えないため。
///
/// 時刻は注入した Clock で測る。上限はタイマーを使わず、次のキー入力（`resolve` / `keyUp`）や `isHolding` を
/// 読んだ時点で判定する。預かっている状態はキー入力の扱いにしか影響しないため、それで足りる。
public struct PaletteEventKeyHold: Sendable {
    /// キーを押してから離すまでを待つ上限。
    /// Issue #90 の再現手順（keyDown → 0.5 秒後から 50ms 間隔で 20 回のリピート → keyUp。約 1.5 秒）や、
    /// 実機 QA の物理キーの約 2 秒の長押しでも、離したときに伝えられる長さにする。
    /// これより長く押し続けるのは確定・閉じるの操作ではないとみなす（UX-001 §1「誤爆防止」）。
    public static let maximumHold: Duration = .seconds(3)
    /// 上限で取り消した後、まだ押し続けているとみなすリピートの間隔の上限。
    /// macOS の「キーのリピート速度」で最も遅い設定の間隔（約 1.8 秒）より長くする。
    public static let repeatTimeout: Duration = .seconds(2)

    /// 預かっているイベント。
    private struct Hold: Sendable {
        let event: PaletteEvent
        let keyCode: UInt16
        /// 生成からの経過時間で表した上限の時刻
        let deadline: Duration
        /// そのキーの keyDown（最初の押下・リピート）を最後に受けた時刻（生成からの経過時間）
        var lastKeyDown: Duration
    }

    private let maximumHold: Duration
    private let repeatTimeout: Duration
    /// 生成からの経過時間。`any Clock<Duration>` の Instant は存在型のままでは比較できないため、経過時間に置き換える
    private let elapsed: @Sendable () -> Duration
    /// 預かっているイベント。上限を過ぎても、そのキーの keyUp・押し直し・取り消し・次のイベントまでは残し、
    /// 取り消したことの報告と、まだ押し続けているかの判定に使う
    private var hold: Hold?

    /// - Parameters:
    ///   - clock: 上限の判定に使う。テストでは手動で進める Clock を渡す。
    ///   - maximumHold: キーを離すまでを待つ上限。
    ///   - repeatTimeout: 上限で取り消した後、まだ押し続けているとみなすリピートの間隔の上限。
    public init<C: Clock<Duration>>(
        clock: C,
        maximumHold: Duration = Self.maximumHold,
        repeatTimeout: Duration = Self.repeatTimeout
    ) {
        let origin = clock.now
        elapsed = { origin.duration(to: clock.now) }
        self.maximumHold = maximumHold
        self.repeatTimeout = repeatTimeout
    }

    /// イベントを預かっていて、上限に達していないか。
    public var isHolding: Bool {
        guard let hold else { return false }
        return !isExpired(hold)
    }

    /// keyDown の扱いを決める。預かったイベントのキーを押し続けている間（`isHolding` と、上限で取り消した後の
    /// リピートの間）はすべて消費し、それ以外は `PaletteKeyBinding` に任せる。
    public mutating func resolve(_ input: PaletteKeyInput) -> PaletteKeyResolution {
        noteKeyDown(input)
        return isKeyStillPressed ? .discard : PaletteKeyBinding.resolve(input)
    }

    /// keyDown の操作で出たパレットのイベントを、そのキーを離すまで預かる。
    /// 確定・閉じるのどちらも、外へ伝えるとパレットがキーを手放すため、すぐには伝えない。
    public mutating func receive(_ event: PaletteEvent, onKeyDownOf keyCode: UInt16) {
        let now = elapsed()
        hold = Hold(event: event, keyCode: keyCode, deadline: now + maximumHold, lastKeyDown: now)
    }

    /// keyUp を受けたときに呼ぶ。
    public mutating func keyUp(keyCode: UInt16) -> PaletteEventKeyRelease {
        guard let hold, hold.keyCode == keyCode else { return .unrelated }
        self.hold = nil
        return isExpired(hold) ? .expired(hold.event) : .send(hold.event)
    }

    /// 預かっているイベントを取り消す（パレットがキーでなくなったとき）。
    /// - Returns: 取り消した、上限に達していないイベント。預かっていない・上限を過ぎていた場合は nil。
    @discardableResult
    public mutating func cancel() -> PaletteEvent? {
        defer { hold = nil }
        return isHolding ? hold?.event : nil
    }

    private func isExpired(_ hold: Hold) -> Bool {
        elapsed() >= hold.deadline
    }

    /// 預かったイベントのキーを押し続けているとみなすか。上限までは常に、上限の後はそのキーのリピートが続いている間。
    private var isKeyStillPressed: Bool {
        guard let hold else { return false }
        let now = elapsed()
        return now < hold.deadline || now - hold.lastKeyDown < repeatTimeout
    }

    /// 預かったイベントのキーの keyDown を記録する。上限で取り消した後に押し直した（リピートでない）場合は、
    /// 前の押下の keyUp を取りこぼしたとみなし、預かっていたイベントを捨てて通常のキーとして扱わせる。
    private mutating func noteKeyDown(_ input: PaletteKeyInput) {
        guard var hold, hold.keyCode == input.keyCode else { return }
        if !input.isRepeat, isExpired(hold) {
            self.hold = nil
            return
        }
        hold.lastKeyDown = elapsed()
        self.hold = hold
    }
}

/// 預かったイベントのキーを離したときの結果。
public enum PaletteEventKeyRelease: Equatable, Sendable {
    /// 預かっていたイベントのキーを上限までに離した。このイベントを外へ伝える
    case send(PaletteEvent)
    /// 預かっていたイベントのキーを、上限を過ぎてから離した。イベントは取り消し済みで、外へは伝えない
    case expired(PaletteEvent)
    /// 預かっていたキーではない（または何も預かっていない）
    case unrelated
}
