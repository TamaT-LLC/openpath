/// AppCoordinator からのパレットの操作（PaletteDisplaying）を、ビューモデル・ウィンドウ・候補の検索に振り分ける
/// （ARCH-001 §5「PanelShown では PaletteWindow を表示し、CandidateIndex に問い合わせる」）。
///
/// - 表示: 別のパネルなら前回の検索語・候補・状態表示を消す（`PaletteViewModel.reset()`）。
///   同じパネルの再表示（Esc 後のホットキー、注入の成功後のホットキー、タイムアウト後の再検知）では、
///   続きから選び直せるよう検索語と選択を保ち、状態表示だけを消す。
/// - 初出の表示: 候補を一度も受け取っていない（別のパネルに切り替えた直後など）ときは、最初の候補が届くまでウィンドウを
///   出さない。空の行のまま出すと、候補が届くまでの数フレームに「一致する候補がありません」が見えてしまうため（#91）。
///   検知から表示までの予算（FR-DETECT-03 の 300ms）を候補の検索で使い切らないよう、待つのは `initialRowsWaitLimit` まで。
///   上限を過ぎたら候補を待たずに出す（候補を受け取るまで 0 件の案内は出さない。`PaletteViewModel.emptyMessage`）。
///   待っている間に候補を引き直した場合（検索語の変更以外の引き直し）は、引き直した結果が届いたときに出す。
/// - 候補: 表示時・検索語の変更時・全件の再構築の完了時・選択モードの推定し直し時・履歴のクリアで候補を取り除いた後に、
///   最新の要求の結果だけを反映する（`PaletteQuerySession`）。
///   ディレクトリに絞るかは候補を引くたびにパネルの推定と設定 include_files から決める。
/// - キー入力: 注入のキー操作の前にパレットを表示したままキー入力をパネルへ返し、失敗を表示したらパレットに戻す。
/// - 表示の記録: 表示するたびに（同じパネルの再表示・ホットキーでの再表示でも）、ウィンドウを出した直後に `palette shown` を
///   info でログに出す。PanelWatcher の `panel detected` と同じパネル ID を含め、両者のタイムスタンプ（ミリ秒）の差で
///   検知レイテンシを測る（FR-DETECT-03、#30）。初出では最初の候補を待ってから出すため、この差には候補の検索の時間
///   （最長 `initialRowsWaitLimit`）が含まれる。待っている間に閉じたパレットは出さないため記録しない。パスは含まない。
@MainActor
public final class PalettePresenter: PaletteDisplaying {
    /// 初出の表示で、最初の候補を待つ上限。空クエリの検索（frecency の上位と存在確認）は通常数十 ms で終わる（#91 の録画で約 33ms）。
    /// 検知（`panel detected`）から表示まで 300ms 以内（FR-DETECT-03）に十分な余裕を残す長さにしている。
    public static let initialRowsWaitLimit: Duration = .milliseconds(100)

    private let viewModel: PaletteViewModel
    private let window: any PaletteWindowControlling
    private let includeFiles: @MainActor () -> Bool
    private let search: PaletteQuerySession.Search
    private let clock: any Clock<Duration>
    private let didShow: @MainActor (PanelContext) -> Void
    private lazy var querySession = PaletteQuerySession(search: search) { [weak self] rows, keepingSelection in
        self?.apply(rows, keepingSelection: keepingSelection)
    }
    /// 表示中のパレットのパネル。閉じている間は nil
    private var presentedPanel: PanelContext?
    /// 最後に表示したパネル。再表示が同じパネルに対するものかの判定に使う
    private var lastPanelID: PanelContext.ID?
    private var buildProgress = CandidateBuildProgress()
    /// 最初の候補を待っている間の、待ちの上限のタイマー。ウィンドウを出していない間だけ持つ
    private var pendingReveal: Task<Void, Never>?
    /// ウィンドウを出しているか。別のパネルの候補を待つ前に、前のパネルのパレットを閉じるかの判定に使う
    private var isWindowShown = false

    /// - Parameters:
    ///   - viewModel: パレットのビューの状態。検索語の変更の通知（`onQueryChange`）はこの型が受け持つ。
    ///   - window: パレットのウィンドウ。
    ///   - includeFiles: 設定 include_files。設定ファイルの変更を反映するため、候補を引くたびに読む。
    ///   - search: 候補の引き方。
    ///   - clock: 初出の表示で最初の候補を待つ上限の計測に使う。テストでは手動で進める Clock を渡す。
    ///   - didShow: ウィンドウを出した直後に、表示のたびに呼ぶ。既定では `palette shown` をログに出す。
    public init(
        viewModel: PaletteViewModel,
        window: any PaletteWindowControlling,
        includeFiles: @escaping @MainActor () -> Bool,
        search: @escaping PaletteQuerySession.Search,
        clock: any Clock<Duration> = ContinuousClock(),
        didShow: @escaping @MainActor (PanelContext) -> Void = PalettePresenter.logShown
    ) {
        self.viewModel = viewModel
        self.window = window
        self.includeFiles = includeFiles
        self.search = search
        self.clock = clock
        self.didShow = didShow
        viewModel.onQueryChange = { [weak self] _ in
            self?.queryDidChange()
        }
    }

    // MARK: - PaletteDisplaying

    public func show(context: PanelContext) {
        let isSamePanel = context.id == lastPanelID
        cancelPendingReveal()
        // reset() による検索語の変更で、前のパネルの条件のまま候補を引かないよう、表示中の扱いを外してから戻す
        presentedPanel = nil
        if isSamePanel {
            viewModel.clearStatus()
        } else {
            viewModel.reset()
        }
        presentedPanel = context
        lastPanelID = context.id
        window.rowCount = viewModel.rows.count
        requestRows(keepingSelection: isSamePanel)
        // 候補を受け取り済みなら（同じパネルの再表示）、その候補のまますぐ出す
        guard viewModel.hasReceivedRows else {
            // 前のパネルのパレットが出たままなら、候補を消したまま前の位置に残さないよう閉じておく
            hideWindow()
            scheduleRevealAfterWaitLimit()
            return
        }
        revealWindow()
    }

    public func update(context: PanelContext) {
        guard let presentedPanel, presentedPanel.id == context.id else { return }
        self.presentedPanel = context
        // まだ出していなければ、出すときに新しい位置を使う
        if presentedPanel.frame != context.frame, !isAwaitingInitialRows {
            window.reposition(near: context.frame)
        }
        // 選択モードの推定し直しでフォルダのみかどうかが変わったときだけ、絞り込みを合わせて引き直す
        guard presentedPanel.isDirectoriesOnly != context.isDirectoriesOnly else { return }
        requestRows(keepingSelection: true)
    }

    public func hide() {
        cancelPendingReveal()
        presentedPanel = nil
        querySession.cancel()
        isWindowShown = false
        window.hide()
    }

    public func setLocked(_ isLocked: Bool) {
        viewModel.setLocked(isLocked)
    }

    public func showStatus(_ message: String) {
        viewModel.showStatus(message)
    }

    public func showError(_ message: String) {
        viewModel.showError(message)
        // 注入の前にキー入力をパネルへ返しているため、パレットを残して再試行できるよう戻す（UX-001 §5）。
        // まだ出していないパレットは、出すときにキー入力を受け取る
        guard presentedPanel != nil, !isAwaitingInitialRows else { return }
        window.reclaimKey()
    }

    // MARK: - 表示の記録

    /// `palette shown` のログの文言。書式は PanelWatcher の `panel detected (id: …, …)` に揃える。
    public nonisolated static func shownLogMessage(for context: PanelContext) -> String {
        "palette shown (id: \(context.id.rawValue))"
    }

    /// 表示の時刻はログのタイムスタンプ（ミリ秒）で分かる。
    public nonisolated static func logShown(_ context: PanelContext) {
        Log.info(shownLogMessage(for: context))
    }

    // MARK: - 配線から呼ぶ操作

    /// 注入のキー操作（⌘⇧G など）の前に呼ぶ。パレットは「パネルへ移動中…」を出したまま、キー入力をパネルへ返す。
    /// `PanelInjector(prepareForKeyEvents:)` に渡す。
    public func releaseKeyForInjection() {
        window.releaseKey()
    }

    /// 候補ソースの全件の再構築（`CandidateIndexRebuilder.isRebuilding`）が変わったときに呼ぶ。
    /// 最初の構築の間だけフッターに構築中を出し、構築を終えたら表示中の候補を選択を保ったまま引き直す。
    public func candidateRebuildingDidChange(_ isRebuilding: Bool) {
        let didFinish = buildProgress.update(isRebuilding: isRebuilding)
        viewModel.setBuildingCandidates(buildProgress.showsBuildingStatus)
        guard didFinish, presentedPanel != nil else { return }
        requestRows(keepingSelection: true)
    }

    /// 全件の再構築の完了とは別に、候補が差し替わったときに呼ぶ（履歴のクリアで履歴の候補を取り除いた後。Issue #92）。
    /// 表示中なら、検索語を変えずに選択を保ったまま候補を引き直す（選択していた候補が消えたら先頭を選ぶ）。
    public func candidatesDidChange() {
        guard presentedPanel != nil else { return }
        requestRows(keepingSelection: true)
    }

    // MARK: - 候補

    private func queryDidChange() {
        guard presentedPanel != nil else { return }
        requestRows(keepingSelection: false)
    }

    private func requestRows(keepingSelection: Bool) {
        guard let presentedPanel else { return }
        querySession.request(
            viewModel.query,
            directoriesOnly: presentedPanel.showsDirectoriesOnly(includeFiles: includeFiles()),
            keepingSelection: keepingSelection
        )
    }

    private func apply(_ rows: [PaletteRow], keepingSelection: Bool) {
        viewModel.replaceRows(rows, keepingSelection: keepingSelection)
        window.rowCount = rows.count
        guard isAwaitingInitialRows else { return }
        // 候補を反映した行数で最初のフレームから描かれるよう、差し替えた後に出す
        revealWindow()
    }

    // MARK: - 初出の表示

    /// ウィンドウを出さずに最初の候補を待っているか
    private var isAwaitingInitialRows: Bool {
        pendingReveal != nil
    }

    private func revealWindow() {
        cancelPendingReveal()
        guard let presentedPanel else { return }
        isWindowShown = true
        window.show(near: presentedPanel.frame)
        didShow(presentedPanel)
    }

    private func hideWindow() {
        guard isWindowShown else { return }
        isWindowShown = false
        window.hide()
    }

    private func scheduleRevealAfterWaitLimit() {
        pendingReveal = Self.makeRevealTimer(on: clock) { [weak self] in
            self?.revealWithoutInitialRows()
        }
    }

    private func revealWithoutInitialRows() {
        guard isAwaitingInitialRows else { return }
        Log.debug("最初の候補が待ちの上限（initialRowsWaitLimit）までに届かなかったため、候補を待たずにパレットを出します")
        revealWindow()
    }

    private func cancelPendingReveal() {
        pendingReveal?.cancel()
        pendingReveal = nil
    }

    /// 期限は呼び出し時点で確定させる。Task の開始が遅れても、待ちの起点がずれないようにするため。
    private static func makeRevealTimer<C: Clock<Duration>>(
        on clock: C,
        onDeadline: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        let deadline = clock.now.advanced(by: initialRowsWaitLimit)
        return Task {
            do {
                try await clock.sleep(until: deadline, tolerance: nil)
            } catch {
                return
            }
            // 期限に達してから続きが走るまでの間に取り消された（別のパネルを出した・閉じた）待ちでは、何もしない。
            // 取り消しも続きも MainActor で行うため、ここで取り消しを確かめれば次のパネルの待ちと取り違えない
            guard !Task.isCancelled else { return }
            onDeadline()
        }
    }
}
