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
///
/// 預けたこと・手放したこと（伝えた・取り消した）を、押していた時間と捨てたキーの数とともに `diagnose` で報告する
/// （`PaletteEventKeyHoldDiagnostic`。既定では debug ログに出す。実機 QA の PAL-08・S-08 の判定用）。
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
        /// 預けた時刻（生成からの経過時間）
        let receivedAt: Duration
        /// 生成からの経過時間で表した上限の時刻
        let deadline: Duration
        /// そのキーの keyDown（最初の押下・リピート）を最後に受けた時刻（生成からの経過時間）
        var lastKeyDown: Duration
        /// 預かっている間に捨てた、そのキーのリピートの数（診断用）
        var discardedRepeatCount = 0
        /// 預かっている間に捨てた、ほかのキーの keyDown の数（診断用）
        var discardedOtherKeyCount = 0
    }

    private let maximumHold: Duration
    private let repeatTimeout: Duration
    /// 生成からの経過時間。`any Clock<Duration>` の Instant は存在型のままでは比較できないため、経過時間に置き換える
    private let elapsed: @Sendable () -> Duration
    private let diagnose: @Sendable (PaletteEventKeyHoldDiagnostic) -> Void
    /// 預かっているイベント。上限を過ぎても、そのキーの keyUp・押し直し・取り消し・次のイベントまでは残し、
    /// 取り消したことの報告と、まだ押し続けているかの判定に使う
    private var hold: Hold?

    /// - Parameters:
    ///   - clock: 上限の判定に使う。テストでは手動で進める Clock を渡す。
    ///   - maximumHold: キーを離すまでを待つ上限。
    ///   - repeatTimeout: 上限で取り消した後、まだ押し続けているとみなすリピートの間隔の上限。
    ///   - diagnose: 預けたこと・手放したことの報告先。既定では debug ログに出す。
    public init<C: Clock<Duration>>(
        clock: C,
        maximumHold: Duration = Self.maximumHold,
        repeatTimeout: Duration = Self.repeatTimeout,
        diagnose: @escaping @Sendable (PaletteEventKeyHoldDiagnostic) -> Void = PaletteEventKeyHoldDiagnostic.log
    ) {
        let origin = clock.now
        elapsed = { origin.duration(to: clock.now) }
        self.maximumHold = maximumHold
        self.repeatTimeout = repeatTimeout
        self.diagnose = diagnose
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
        guard isKeyStillPressed else { return PaletteKeyBinding.resolve(input) }
        countDiscarded(input)
        return .discard
    }

    /// keyDown の操作で出たパレットのイベントを、そのキーを離すまで預かる。
    /// 確定・閉じるのどちらも、外へ伝えるとパレットがキーを手放すため、すぐには伝えない。
    public mutating func receive(_ event: PaletteEvent, onKeyDownOf keyCode: UInt16) {
        let now = elapsed()
        // 上限の後にリピートが途切れ、前のキーの keyUp を取りこぼしたまま次の操作をした
        if let previous = hold {
            end(previous, .replaced, at: now)
        }
        let newHold = Hold(event: event, keyCode: keyCode, receivedAt: now, deadline: now + maximumHold, lastKeyDown: now)
        hold = newHold
        diagnose(.started(record(of: newHold, at: now)))
    }

    /// keyUp を受けたときに呼ぶ。
    public mutating func keyUp(keyCode: UInt16) -> PaletteEventKeyRelease {
        guard let hold, hold.keyCode == keyCode else { return .unrelated }
        self.hold = nil
        let now = elapsed()
        let isExpired = now >= hold.deadline
        end(hold, isExpired ? .expired : .sent, at: now)
        return isExpired ? .expired(hold.event) : .send(hold.event)
    }

    /// 預かっているイベントを取り消す（パレットがキーでなくなったとき）。
    /// - Returns: 取り消した、上限に達していないイベント。預かっていない・上限を過ぎていた場合は nil。
    @discardableResult
    public mutating func cancel() -> PaletteEvent? {
        guard let hold else { return nil }
        self.hold = nil
        let now = elapsed()
        end(hold, .canceled, at: now)
        return now < hold.deadline ? hold.event : nil
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
            end(hold, .repressed, at: elapsed())
            return
        }
        hold.lastKeyDown = elapsed()
        self.hold = hold
    }

    /// 押し続けているとみなして捨てた keyDown を数える（診断用）。
    /// 同じキーのリピートでない keyDown（keyUp を取りこぼしたまま上限の前に押し直した等）は、リピートではないため数えない。
    private mutating func countDiscarded(_ input: PaletteKeyInput) {
        guard var hold else { return }
        if input.keyCode != hold.keyCode {
            hold.discardedOtherKeyCount += 1
        } else if input.isRepeat {
            hold.discardedRepeatCount += 1
        }
        self.hold = hold
    }

    /// 預かっていたイベントを手放したことを報告する。
    private func end(_ hold: Hold, _ reason: PaletteKeyHoldEnd, at now: Duration) {
        diagnose(.ended(record(of: hold, at: now), reason))
    }

    private func record(of hold: Hold, at now: Duration) -> PaletteKeyHoldRecord {
        PaletteKeyHoldRecord(
            event: PaletteKeyHoldRecord.Event(hold.event),
            keyCode: hold.keyCode,
            heldDuration: now - hold.receivedAt,
            isLimitReached: now >= hold.deadline,
            discardedRepeatCount: hold.discardedRepeatCount,
            discardedOtherKeyCount: hold.discardedOtherKeyCount
        )
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
