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
            // タイムアウトで Idle に戻った後もエラー表示のパレットが残り得るため、閉じておく
            palette.hide()
        case .panelShown:
            state = .idle
            palette.hide()
        case .injecting:
            cancelActiveInjection()
            state = .idle
            palette.setLocked(false)
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
        guard case .panelShown(let context, isPaletteVisible: false) = state else { return }
        showPalette(for: context)
    }

    private func showPalette(for context: PanelContext) {
        state = .panelShown(context, isPaletteVisible: true)
        palette.show(context: context)
    }

    // MARK: - 注入

    private func startInjection(context: PanelContext, path: String, autoConfirm: Bool) {
        let injectionID = nextInjectionID
        nextInjectionID += 1
        activeInjection = ActiveInjection(
            id: injectionID,
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

    private func finishInjection(id: Int, outcome: InjectionOutcome) {
        // 取り消し済み・置き換え済みの注入から遅れて届いた結果は捨てる
        guard activeInjection?.id == id, case .injecting(let context, let path) = state else { return }
        cancelActiveInjection()

        switch outcome {
        case .succeeded:
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
    let work: Task<Void, Never>
    let timeout: Task<Void, Never>

    func cancel() {
        work.cancel()
        timeout.cancel()
    }
}
