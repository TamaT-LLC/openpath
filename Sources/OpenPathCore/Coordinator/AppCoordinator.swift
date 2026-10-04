/// パネル検知からパス注入までを司る状態機械（ARCH-001 §5）。
/// PanelWatcher / PaletteWindow / ホットキーから UI スレッドで呼ばれるため MainActor に隔離する。
///
/// 注入の開始と、注入の失敗を覚える・出し直す・忘れることを `diagnose` で報告する
/// （`CoordinatorDiagnostic`。既定では debug ログに出す。実機 QA の INJ-01 の判定用）。
@MainActor
public final class AppCoordinator {
    /// 注入の全体タイムアウト。超えたらパネルの状態が不明とみなして Idle に戻す。
    /// macOS 26 の VS Code の初回の注入（移動先シートが ③ で約 900ms に開く）が、ペーストと確定までに 1.5 秒を超えたため、
    /// 2.5 秒にしている（Issue #29）。失敗する注入は injector の各段の待ち（`PathInjectionTiming` など）で先に打ち切られるため、
    /// 延ばしても待たされるのは遅いが成功する注入だけになる。
    public static let injectionTimeout: Duration = .milliseconds(2500)

    public private(set) var state: CoordinatorState = .idle {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    /// 状態が変わるたびに呼ばれる。PanelWatcher の補助ポーリングを PanelShown 中だけ止める（DSN-001 §2.1）等に使う。
    /// 通知の途中で状態が変わらないよう、この中から `handle(_:)` を同期的に呼ばないこと。
    public var onStateChange: (@MainActor (CoordinatorState) -> Void)?

    /// パレットを閉じた後に分かった注入のエラーのうち、利用者が気づくべきものを伝える。
    /// 自動確定では「開く」でパネルが閉じ、パレットも閉じるため、クリップボードを元に戻せなかったこと
    /// （`InjectionError.pasteboardRestoreFailed`）をパレットでは伝えられない。メニューバーのバッジ等で知らせる。
    public var onErrorOutsidePalette: (@MainActor (InjectionError) -> Void)?

    private let palette: any PaletteDisplaying
    private let injector: any PathInjecting
    private let history: any HistoryRecording
    private let isAutoConfirmEnabled: @MainActor () -> Bool
    private let clock: any Clock<Duration>
    private let diagnose: @MainActor (CoordinatorDiagnostic) -> Void
    private var activeInjection: ActiveInjection?
    private var nextInjectionID = 0
    /// 注入に成功し、まだ開いているはずのパネル。Idle 中だけ持つ。
    /// PanelWatcher は Idle に戻ると開いたままのパネルを再通知する。注入に成功したパネルでは、ユーザーがパネル側で
    /// Enter（「開く」）を押して確定するため（UX-001 §2）、再通知でパレットを出し直してキー入力を奪わないよう無視する。
    /// ホットキーは明示的な再表示（UX-001 §4）なので、このパネルのパレットを出す。
    private var injectedPanel: PanelContext?
    /// 自動確定の注入がクリップボードの復元失敗で終わった後、まだパネルの消滅を受けていない確定。PanelShown 中だけ持つ。
    /// 「開く」でパネルが閉じても、PanelWatcher の panelGone は注入の結果より遅れて届くことがある。
    /// そのまま panelGone が届いたら、パネルの消滅を根拠に履歴に残し、閉じるパレットの代わりにパレットの外へ知らせる。
    /// 利用者がパレットを操作したら（Esc・再試行・再表示）、パネルの消滅は「開く」によるものとみなさない。
    private var pendingRestoreFailure: PendingRestoreFailure?
    /// パレットに出している注入の失敗。PanelShown（パレット表示）中だけ持つ。
    /// アプリの切り替えなどでパネルを見失ったら `failureToReshow` に移し、戻ったときに出し直す。
    /// 利用者がパレットを操作したら（Esc・再試行・再表示）、見たものとして忘れる。
    private var displayedFailure: PanelFailure?
    /// パネルを見失ったためにパレットで見せられなかった（または見せていたパレットを閉じた）注入の失敗。Idle 中だけ持つ。
    /// PanelWatcher はアプリを切り替えると panelGone を送り、元のアプリに戻ると開いたままのパネルを再通知する（PR #46）。
    /// 切り替えている間は他のアプリの上にパレットを出さず、同じパネルの再通知でパレットにこの失敗を付けて出す（#94）。
    /// パレットの表示中に全体タイムアウト（2.5 秒）で Idle に戻ったときも、エラーを出したパレットを残したまま持つ。
    /// PanelWatcher は Idle に戻ると開いたままのパネルを再通知するため、パレットを出し直すときに付け直す（#101）。
    /// 別のパネルのパレットを出したら忘れる。Idle で残ったパレットを Esc で閉じたら、見たものとして忘れる。
    /// パネルの id は使い回されない（OpenPanelLocator の連番）ため期限は設けない。
    private var failureToReshow: PanelFailure?

    /// - Parameters:
    ///   - isAutoConfirmEnabled: 設定 auto_confirm。設定ファイルの変更を反映するため confirm のたびに読む。
    ///   - clock: 注入タイムアウトの計測に使う。テストでは手動で進める Clock を渡す。
    ///   - diagnose: 注入の開始と、注入の失敗の記憶の報告先。既定では debug ログに出す。
    public init(
        palette: any PaletteDisplaying,
        injector: any PathInjecting,
        history: any HistoryRecording,
        isAutoConfirmEnabled: @escaping @MainActor () -> Bool,
        clock: any Clock<Duration> = ContinuousClock(),
        diagnose: @escaping @MainActor (CoordinatorDiagnostic) -> Void = CoordinatorDiagnostic.log
    ) {
        self.palette = palette
        self.injector = injector
        self.history = history
        self.isAutoConfirmEnabled = isAutoConfirmEnabled
        self.clock = clock
        self.diagnose = diagnose
    }

    public func handle(_ event: CoordinatorEvent) {
        switch event {
        case .panelAppeared(let context):
            panelAppeared(context)
        case .panelGone:
            panelGone()
        case .panelContextChanged(let context):
            panelContextChanged(context)
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
            let failure = takeFailureToReshow(for: context.id)
            showPalette(for: context, forgetting: .otherPanel)
            // 切り替えている間に終えた注入の失敗（#94）や、タイムアウトで出したエラー（#101）を、
            // 出し直したパレットで伝える（検索語と選択は PalettePresenter が保つ）
            if let failure {
                showFailure(failure)
                diagnose(.failureReshown(panelID: failure.panelID, failure: failure.kind))
            }
        case .panelShown(let current, _):
            // 同じパネルの再検知で、Esc で閉じたパレットを勝手に出し直さない
            guard current.id != context.id else { return }
            showPalette(for: context, forgetting: .otherPanel)
        case .injecting:
            return
        }
    }

    private func panelGone() {
        switch state {
        case .idle:
            injectedPanel = nil
            // タイムアウトで Idle に戻った後もエラー表示のパレットが残り得るため、閉じておく。
            // 覚えたエラーは、同じパネルが戻ってきたときに出し直すため忘れない（#101）
            palette.hide()
        case .panelShown(let context, _):
            let restoreFailure = pendingRestoreFailure
            let failure = displayedFailure
            pendingRestoreFailure = nil
            displayedFailure = nil
            if let restoreFailure, restoreFailure.panelID == context.id {
                if let failure {
                    diagnose(.failureForgotten(panelID: failure.panelID, failure: failure.kind, reason: .panelClosed))
                }
                state = .idle
                palette.hide()
                history.record(path: restoreFailure.path)
                onErrorOutsidePalette?(.pasteboardRestoreFailed)
                return
            }
            // 失敗を出していたパネルを見失った（アプリの切り替え等）。戻ってきたら出し直す
            if let failure, failure.panelID == context.id {
                rememberFailure(failure, cause: .panelGoneWhileShowingFailure)
            } else {
                // 別のパネルの失敗が残っていた場合（通常は起きない）も、診断の経路を揃えて捨てたことを報告する
                if let failure {
                    diagnose(.failureForgotten(panelID: failure.panelID, failure: failure.kind, reason: .otherPanel))
                }
                forgetFailureToReshow(.otherPanel)
            }
            state = .idle
            palette.hide()
        case .injecting(let context, _):
            guard activeInjection?.shouldAwaitResultAfterPanelGone == true else {
                cancelActiveInjection()
                // 注入の途中でパネルを見失った（アプリの切り替え等）ため打ち切った。パネルが最前面でなくなったときと同じく、
                // 戻ってきたパネルの再通知で、移動できなかったことを伝える
                rememberFailure(
                    PanelFailure(panelID: context.id, error: InjectionError.targetNotFrontmost),
                    cause: .panelGoneWhileInjecting
                )
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

    /// 追跡中のパネルの情報を差し替える。パレットの表示中はパレットにも知らせ、
    /// それ以外（Esc で閉じた間・注入中・注入の成功後）は、次にパレットを出すときに使う。
    private func panelContextChanged(_ context: PanelContext) {
        switch state {
        case .idle:
            guard injectedPanel?.id == context.id else { return }
            injectedPanel = context
        case .panelShown(let current, let isPaletteVisible):
            guard current.id == context.id else { return }
            state = .panelShown(context, isPaletteVisible: isPaletteVisible)
            if isPaletteVisible {
                palette.update(context: context)
            }
        case .injecting(let current, let path):
            guard current.id == context.id else { return }
            state = .injecting(context, path: path)
            // 注入中もパレットは表示したまま。失敗して PanelShown に戻ったときに新しい情報で候補を引けるよう伝えておく
            palette.update(context: context)
        }
    }

    private func confirm(path: String, openImmediately: Bool) {
        guard case .panelShown(let context, isPaletteVisible: true) = state, !path.isEmpty else { return }
        startInjection(context: context, path: path, autoConfirm: openImmediately || isAutoConfirmEnabled())
    }

    private func escape() {
        switch state {
        case .idle:
            // タイムアウト後に残ったエラー表示のパレットを閉じられるようにする。
            // Esc はパレットにキーがあるときだけ届くため、出していたエラーは利用者が見たものとして忘れる
            forgetFailureToReshow(.escape)
            palette.hide()
        case .panelShown(let context, isPaletteVisible: true):
            pendingRestoreFailure = nil
            forgetDisplayedFailure(.escape)
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
            showPalette(for: injectedPanel, forgetting: .hotkey)
        case .panelShown(let context, isPaletteVisible: false):
            showPalette(for: context, forgetting: .hotkey)
        case .panelShown(_, isPaletteVisible: true), .injecting:
            return
        }
    }

    /// - Parameter reason: 覚えていた失敗が残っていた場合に、忘れた理由として報告するもの。
    private func showPalette(for context: PanelContext, forgetting reason: CoordinatorDiagnostic.ForgetReason) {
        injectedPanel = nil
        pendingRestoreFailure = nil
        forgetDisplayedFailure(reason)
        forgetFailureToReshow(reason)
        state = .panelShown(context, isPaletteVisible: true)
        palette.show(context: context)
    }

    /// 表示中のパレットに注入の失敗を赤字で出し、パネルを見失ったときに出し直せるよう覚えておく。
    private func showFailure(_ failure: PanelFailure) {
        displayedFailure = failure
        palette.showError(failure.message)
    }

    // MARK: - 失敗の記憶（診断の報告を伴う）

    /// 同じパネルの再通知で出し直す失敗として覚える。
    private func rememberFailure(_ failure: PanelFailure, cause: CoordinatorDiagnostic.RememberCause) {
        failureToReshow = failure
        diagnose(.failureRemembered(panelID: failure.panelID, failure: failure.kind, cause: cause))
    }

    /// `panelID` のパネルの出し直す失敗を取り出す（出し直すため、忘れたとは報告しない）。別のパネルの失敗は残す。
    private func takeFailureToReshow(for panelID: PanelContext.ID) -> PanelFailure? {
        guard let failure = failureToReshow, failure.panelID == panelID else { return nil }
        failureToReshow = nil
        return failure
    }

    private func forgetFailureToReshow(_ reason: CoordinatorDiagnostic.ForgetReason) {
        guard let failure = failureToReshow else { return }
        failureToReshow = nil
        diagnose(.failureForgotten(panelID: failure.panelID, failure: failure.kind, reason: reason))
    }

    private func forgetDisplayedFailure(_ reason: CoordinatorDiagnostic.ForgetReason) {
        guard let failure = displayedFailure else { return }
        displayedFailure = nil
        diagnose(.failureForgotten(panelID: failure.panelID, failure: failure.kind, reason: reason))
    }

    // MARK: - 注入

    private func startInjection(context: PanelContext, path: String, autoConfirm: Bool) {
        // 失敗を表示しているパレットからの確定は、再試行
        let isRetry = displayedFailure != nil
        pendingRestoreFailure = nil
        forgetDisplayedFailure(.retry)
        diagnose(.injectionStarted(panelID: context.id, isAutoConfirm: autoConfirm, isRetry: isRetry))
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

    /// 期限は呼び出し時点で確定させる。Task の開始が遅れても全体タイムアウトの起点がずれないようにするため。
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
            finishInjectionAfterPanelGone(context: context, path: path, outcome: outcome)
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
            if injection.isAutoConfirm, error as? InjectionError == .pasteboardRestoreFailed {
                pendingRestoreFailure = PendingRestoreFailure(panelID: context.id, path: path)
            }
            palette.setLocked(false)
            showFailure(PanelFailure(panelID: context.id, error: error))
        case .timedOut:
            // パネルの状態が分からないため Idle に戻し、エラーを出したパレットは残す。PanelWatcher は Idle に戻ると
            // 開いたままのパネルを再通知し、パレットを出し直すと状態表示が消えるため、そのときに付け直せるよう覚えておく（#101）
            let failure = PanelFailure.timedOut(panelID: context.id)
            rememberFailure(failure, cause: .timedOut)
            state = .idle
            palette.setLocked(false)
            palette.showError(failure.message)
        }
    }

    /// 自動確定中にパネルが消えた注入を終える。パレットは閉じ済みのため、結果にかかわらずエラーはその場では出さない。
    private func finishInjectionAfterPanelGone(context: PanelContext, path: String, outcome: InjectionOutcome) {
        switch outcome {
        case .succeeded, .failed(InjectionError.panelGone):
            // 「開く」の押下でパネルが閉じたとみなす。押下まで進んだかは Coordinator からは分からないため、
            // injector がパネルの消滅（panelGone）で終えた場合も、パネルの消滅を根拠に成功として扱う
            finishAsIdle()
            history.record(path: path)
        case .failed(InjectionError.pasteboardRestoreFailed):
            // 元の結果より優先して伝えられるペーストボードの復元失敗も、パネルの消滅を根拠に成功として扱う。
            // クリップボードが失われたことはパレットで伝えられないため、外へ知らせる
            finishAsIdle()
            history.record(path: path)
            onErrorOutsidePalette?(.pasteboardRestoreFailed)
        case .failed(InjectionError.panelGoneBeforeConfirm):
            // 「開く」を押す前にパネルが閉じられた。パネルは戻ってこないため、何も伝えない
            finishAsIdle()
        case .failed(let error):
            // 「開く」まで進まなかった（targetNotFrontmost 等）。パネルが消えたのはアプリの切り替えによるもので、
            // 開いたまま戻ってくることがあるため、同じパネルの再通知で失敗を伝える
            rememberFailure(PanelFailure(panelID: context.id, error: error), cause: .finishedAfterPanelGone)
            finishAsIdle()
        case .timedOut:
            rememberFailure(PanelFailure.timedOut(panelID: context.id), cause: .finishedAfterPanelGone)
            finishAsIdle()
        }
    }

    private func finishAsIdle() {
        state = .idle
        palette.setLocked(false)
    }

    private func cancelActiveInjection() {
        activeInjection?.cancel()
        activeInjection = nil
    }
}

/// パネルの消滅を待っている、自動確定のクリップボードの復元失敗。
private struct PendingRestoreFailure {
    let panelID: PanelContext.ID
    let path: String
}

/// パレットに出す（出した）注入の失敗と、その注入先のパネル。
private struct PanelFailure {
    let panelID: PanelContext.ID
    let message: String
    /// 診断の報告に使う失敗の種類
    let kind: CoordinatorDiagnostic.FailureKind

    init(panelID: PanelContext.ID, error: any Error) {
        self.panelID = panelID
        message = Self.message(for: error)
        kind = CoordinatorDiagnostic.FailureKind(error)
    }

    /// AppCoordinator の全体タイムアウト（文言は `PaletteMessage.injectionTimedOut`）。
    static func timedOut(panelID: PanelContext.ID) -> PanelFailure {
        PanelFailure(panelID: panelID, error: InjectionError.timeout(step: .overall))
    }

    /// パレットのフッターに出す文言。InjectionError 以外や文言の無いエラーは汎用の文言にする。
    private static func message(for error: any Error) -> String {
        (error as? InjectionError)?.userMessage ?? PaletteMessage.injectionFailed
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
