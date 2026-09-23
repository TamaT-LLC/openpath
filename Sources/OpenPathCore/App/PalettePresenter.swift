/// AppCoordinator からのパレットの操作（PaletteDisplaying）を、ビューモデル・ウィンドウ・候補の検索に振り分ける
/// （ARCH-001 §5「PanelShown では PaletteWindow を表示し、CandidateIndex に問い合わせる」）。
///
/// - 表示: 別のパネルなら前回の検索語・候補・状態表示を消す（`PaletteViewModel.reset()`）。
///   同じパネルの再表示（Esc 後のホットキー、注入の成功後のホットキー、タイムアウト後の再検知）では、
///   続きから選び直せるよう検索語と選択を保ち、状態表示だけを消す。
/// - 候補: 表示時・検索語の変更時・全件の再構築の完了時に、最新の要求の結果だけを反映する（`PaletteQuerySession`）。
///   ディレクトリに絞るかは候補を引くたびにパネルの推定と設定 include_files から決める。
/// - キー入力: 注入のキー操作の前にパレットを表示したままキー入力をパネルへ返し、失敗を表示したらパレットに戻す。
@MainActor
public final class PalettePresenter: PaletteDisplaying {
    private let viewModel: PaletteViewModel
    private let window: any PaletteWindowControlling
    private let includeFiles: @MainActor () -> Bool
    private let search: PaletteQuerySession.Search
    private lazy var querySession = PaletteQuerySession(search: search) { [weak self] rows, keepingSelection in
        self?.apply(rows, keepingSelection: keepingSelection)
    }
    /// 表示中のパレットのパネル。閉じている間は nil
    private var presentedPanel: PanelContext?
    /// 最後に表示したパネル。再表示が同じパネルに対するものかの判定に使う
    private var lastPanelID: PanelContext.ID?
    private var buildProgress = CandidateBuildProgress()

    /// - Parameters:
    ///   - viewModel: パレットのビューの状態。検索語の変更の通知（`onQueryChange`）はこの型が受け持つ。
    ///   - window: パレットのウィンドウ。
    ///   - includeFiles: 設定 include_files。設定ファイルの変更を反映するため、候補を引くたびに読む。
    ///   - search: 候補の引き方。
    public init(
        viewModel: PaletteViewModel,
        window: any PaletteWindowControlling,
        includeFiles: @escaping @MainActor () -> Bool,
        search: @escaping PaletteQuerySession.Search
    ) {
        self.viewModel = viewModel
        self.window = window
        self.includeFiles = includeFiles
        self.search = search
        viewModel.onQueryChange = { [weak self] _ in
            self?.queryDidChange()
        }
    }

    // MARK: - PaletteDisplaying

    public func show(context: PanelContext) {
        let isSamePanel = context.id == lastPanelID
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
        window.show(near: context.frame)
    }

    public func hide() {
        presentedPanel = nil
        querySession.cancel()
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
        // 注入の前にキー入力をパネルへ返しているため、パレットを残して再試行できるよう戻す（UX-001 §5）
        guard presentedPanel != nil else { return }
        window.reclaimKey()
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
    }
}
