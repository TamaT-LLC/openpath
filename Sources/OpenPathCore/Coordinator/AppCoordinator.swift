/// パネル検知からパス注入までを司る状態機械（ARCH-001 §5）。
/// PanelWatcher / PaletteWindow / ホットキーから UI スレッドで呼ばれるため MainActor に隔離する。
@MainActor
public final class AppCoordinator {
    /// 注入の全体タイムアウト。超えたらパネルの状態が不明とみなして Idle に戻す。
    public static let injectionTimeout: Duration = .milliseconds(1500)

    public private(set) var state: CoordinatorState = .idle {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    /// 状態が変わるたびに呼ばれる。PanelWatcher の補助ポーリングを PanelShown 中だけ止める（DSN-001 §2.1）等に使う。
    /// 通知の途中で状態が変わらないよう、この中から `handle(_:)` を同期的に呼ばないこと。
    public var onStateChange: (@MainActor (CoordinatorState) -> Void)?

    private let palette: any PaletteDisplaying
    private let injector: any PathInjecting
    private let history: any HistoryRecording
    private let isAutoConfirmEnabled: @MainActor () -> Bool
    private let clock: any Clock<Duration>
    private var activeInjection: ActiveInjection?
    private var nextInjectionID = 0
    /// 注入に成功し、まだ開いているはずのパネル。Idle 中だけ持つ。
    /// PanelWatcher は Idle に戻ると開いたままのパネルを再通知する。注入に成功したパネルでは、ユーザーがパネル側で
    /// Enter（「開く」）を押して確定するため（UX-001 §2）、再通知でパレットを出し直してキー入力を奪わないよう無視する。
    /// ホットキーは明示的な再表示（UX-001 §4）なので、このパネルのパレットを出す。
    private var injectedPanel: PanelContext?

    /// - Parameters:
    ///   - isAutoConfirmEnabled: 設定 auto_confirm。設定ファイルの変更を反映するため confirm のたびに読む。
    ///   - clock: 注入タイムアウトの計測に使う。テストでは手動で進める Clock を渡す。
    public init(
        palette: any PaletteDisplaying,
        injector: any PathInjecting,
        history: any HistoryRecording,
        isAutoConfirmEnabled: @escaping @MainActor () -> Bool,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.palette = palette
        self.injector = injector
        self.history = history
        self.isAutoConfirmEnabled = isAutoConfirmEnabled
        self.clock = clock
    }

    public func handle(_ event: CoordinatorEvent) {
        switch event {
        case .panelAppeared(let context):
            panelAppeared(context)
        case .panelGone:
            panelGone()
        case .confirm(let path, let openImmediately):
            confirm(path: path, openImmediately: openImmediately)
        case .escape:
            escape()
        case .hotkey:
            hotkey()
        }
    }

    // MARK: - イベントごとの遷移

    private func panelAppeared(_ context: PanelContext) {
        switch state {
        case .idle:
            // 注入に成功したパネルの再通知では、パネル側での確定（Enter）を妨げないようパレットを出さない
            guard injectedPanel?.id != context.id else { return }
            showPalette(for: context)
        case .panelShown(let current, _):
            // 同じパネルの再検知で、Esc で閉じたパレットを勝手に出し直さない
            guard current.id != context.id else { return }
            showPalette(for: context)
        case .injecting:
            return
        }
    }

    private func panelGone() {
        switch state {
        case .idle:
            injectedPanel = nil
            // タイムアウトで Idle に戻った後もエラー表示のパレットが残り得るため、閉じておく
            palette.hide()
        case .panelShown:
            state = .idle
            palette.hide()
        case .injecting:
            guard activeInjection?.shouldAwaitResultAfterPanelGone == true else {
                cancelActiveInjection()
                state = .idle
                palette.setLocked(false)
                palette.hide()
                return
            }
            // 自動確定では injector が最後に「開く」を押し、注入の完了より先にパネルが消える。
            // 注入はキャンセルせず、結果を待って履歴に残す（タイムアウトは維持する）
            activeInjection?.isPanelGone = true
            palette.hide()
        }
    }

    private func confirm(path: String, openImmediately: Bool) {
        guard case .panelShown(let context, isPaletteVisible: true) = state, !path.isEmpty else { return }
        startInjection(context: context, path: path, autoConfirm: openImmediately || isAutoConfirmEnabled())
    }

    private func escape() {
        switch state {
        case .idle:
            // タイムアウト後に残ったエラー表示のパレットを閉じられるようにする
            palette.hide()
        case .panelShown(let context, isPaletteVisible: true):
            state = .panelShown(context, isPaletteVisible: false)
            palette.hide()
        case .panelShown(_, isPaletteVisible: false), .injecting:
            return
        }
    }

    private func hotkey() {
        switch state {
        case .idle:
            // タイムアウト後などは、開いたままのパネルの再通知でパレットを出し直す（PanelWatcher 側の責務）
            guard let injectedPanel else { return }
            showPalette(for: injectedPanel)
        case .panelShown(let context, isPaletteVisible: false):
            showPalette(for: context)
        case .panelShown(_, isPaletteVisible: true), .injecting:
            return
        }
    }

    private func showPalette(for context: PanelContext) {
        injectedPanel = nil
        state = .panelShown(context, isPaletteVisible: true)
        palette.show(context: context)
    }

    // MARK: - 注入

    private func startInjection(context: PanelContext, path: String, autoConfirm: Bool) {
        let injectionID = nextInjectionID
        nextInjectionID += 1
        activeInjection = ActiveInjection(
            id: injectionID,
            isAutoConfirm: autoConfirm,
            work: makeInjectionTask(id: injectionID, path: path, autoConfirm: autoConfirm),
            timeout: Self.makeTimeoutTask(on: clock) { [weak self] in
                self?.finishInjection(id: injectionID, outcome: .timedOut)
            }
        )
        state = .injecting(context, path: path)
        palette.setLocked(true)
        palette.showStatus(PaletteMessage.injecting)
    }

    private func makeInjectionTask(id: Int, path: String, autoConfirm: Bool) -> Task<Void, Never> {
        Task { [weak self, injector] in
            // confirm 直後にパネル消滅等で取り消された場合、無関係なウィンドウへキー入力を送らない
            guard !Task.isCancelled else { return }
            self?.injectionDidStart(id: id)
            let outcome: InjectionOutcome
            do {
                try await injector.inject(path: path, autoConfirm: autoConfirm)
                outcome = .succeeded
            } catch {
                outcome = .failed(error)
            }
            self?.finishInjection(id: id, outcome: outcome)
        }
    }

    /// 期限は呼び出し時点で確定させる。Task の開始が遅れても 1.5 秒の起点がずれないようにするため。
    private static func makeTimeoutTask<C: Clock<Duration>>(
        on clock: C,
        onTimeout: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        let deadline = clock.now.advanced(by: injectionTimeout)
        return Task {
            do {
                try await clock.sleep(until: deadline, tolerance: nil)
            } catch {
                return
            }
            onTimeout()
        }
    }

    private func injectionDidStart(id: Int) {
        guard activeInjection?.id == id else { return }
        activeInjection?.hasStarted = true
    }

    private func finishInjection(id: Int, outcome: InjectionOutcome) {
        // 取り消し済み・置き換え済みの注入から遅れて届いた結果は捨てる
        guard let injection = activeInjection, injection.id == id,
              case .injecting(let context, let path) = state else { return }
        cancelActiveInjection()

        if injection.isPanelGone {
            finishInjectionAfterPanelGone(path: path, outcome: outcome)
            return
        }
        switch outcome {
        case .succeeded:
            // パネルは開いたまま。ユーザーがパネル側で確定するまで、同じパネルの再通知ではパレットを出さない
            injectedPanel = context
            state = .idle
            palette.setLocked(false)
            palette.hide()
            history.record(path: path)
        case .failed(InjectionError.panelGone):
            state = .idle
            palette.setLocked(false)
            palette.hide()
        case .failed(let error):
            // 失敗はパレットを残し、そのまま再試行できるようにする（UX-001 §5）
            state = .panelShown(context, isPaletteVisible: true)
            palette.setLocked(false)
            palette.showError((error as? InjectionError)?.userMessage ?? PaletteMessage.injectionFailed)
        case .timedOut:
            state = .idle
            palette.setLocked(false)
            palette.showError(PaletteMessage.injectionTimedOut)
        }
    }

    /// 自動確定中にパネルが消えた注入を終える。パレットは閉じ済みのため、結果にかかわらずエラーは出さない。
    private func finishInjectionAfterPanelGone(path: String, outcome: InjectionOutcome) {
        state = .idle
        palette.setLocked(false)
        switch outcome {
        case .succeeded, .failed(InjectionError.panelGone), .failed(InjectionError.pasteboardRestoreFailed):
            // 「開く」の押下でパネルが閉じたとみなす。押下まで進んだかは Coordinator からは分からないため、
            // injector がパネルの消滅（panelGone）で終えた場合と、元の結果より優先して伝えられる
            // ペーストボードの復元失敗で終えた場合も、パネルの消滅を根拠に成功として扱う
            history.record(path: path)
        case .failed, .timedOut:
            return
        }
    }

    private func cancelActiveInjection() {
        activeInjection?.cancel()
        activeInjection = nil
    }
}

private enum InjectionOutcome {
    case succeeded
    case failed(any Error)
    case timedOut
}

/// 実行中の注入と、その全体タイムアウトの組。
private struct ActiveInjection {
    let id: Int
    /// 最後に「開く」を押す注入か（auto_confirm または Cmd+Enter）。
    let isAutoConfirm: Bool
    let work: Task<Void, Never>
    let timeout: Task<Void, Never>
    /// injector の呼び出しを始めたか。始める前のパネル消滅は「開く」の押下によるものではない。
    var hasStarted = false
    /// 注入中にパネルの消滅を受けたか。
    var isPanelGone = false

    /// パネルが消えても注入を続け、結果を待つか。
    var shouldAwaitResultAfterPanelGone: Bool {
        isAutoConfirm && hasStarted
    }

    func cancel() {
        work.cancel()
        timeout.cancel()
    }
}
