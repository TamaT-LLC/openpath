import OpenPathCore

/// アプリの各モジュールを生成して配線し、AppLifecycle の段階ごとに始める・止める（ARCH-001 §3〜§5）。
///
/// 配線:
/// - PanelWatcher → AppCoordinator（パネルの出現・消滅）、AppCoordinator → PanelWatcher（状態。PanelShown 中は補助ポーリングを止める）
/// - AppCoordinator → パレット（PalettePresenter）→ CandidateIndex（検索語ごとの候補）
/// - パレットの確定 → AppCoordinator → PanelInjector → 履歴（HistoryStore）→ 候補の履歴の取り直し
/// - グローバルホットキー → AppCoordinator（パレットの再表示）
/// - ConfigStore の変更 → 候補の再構築（CandidateIndexRebuilder）・ホットキーの差し替え・disabled_apps の判定し直し
@MainActor
final class AppServices {
    let configStore: ConfigStore
    private let historyStore: HistoryStore
    private let rebuilder: CandidateIndexRebuilder
    private let palette: PaletteAssembly
    private let coordinator: AppCoordinator
    private let panelWatcher: PanelWatcher
    private let globalHotkey: GlobalHotkey
    /// ホットキーを登録しておくべきか。設定の変更で差し替えるかの判定に使う（初回の登録に失敗しても後の変更で登録し直す）
    private var isHotkeyEnabled = false
    /// 最後に反映した設定。変わった項目だけを各モジュールへ伝えるために使う
    private var appliedConfig: Config?
    private var configChangesTask: Task<Void, Never>?
    private var rebuildingObservation: ObservationRelay<Bool>?

    /// 自動確定でパレットを閉じた後に分かった、利用者が気づくべき注入のエラー（`AppCoordinator.onErrorOutsidePalette`）
    var onErrorOutsidePalette: (@MainActor @Sendable (InjectionError) -> Void)? {
        get { coordinator.onErrorOutsidePalette }
        set { coordinator.onErrorOutsidePalette = newValue }
    }

    init() {
        // login shell の起動を繰り返さないよう、ghq root の取得（設定の既定値）と候補の ghq ソースで共有する
        let searchPathResolver = LoginShellPathResolver()
        let configStore = ConfigStore(
            directory: ConfigStore.defaultDirectory(),
            ghqRootProvider: GhqRepositoryLister(isEnabled: true, searchPathProvider: searchPathResolver)
        )
        let historyStore = HistoryStore(persistence: HistoryFile(directory: HistoryFile.defaultDirectory))
        let index = CandidateIndex(historyStore: historyStore)
        let rebuilder = CandidateIndexRebuilder(
            index: index,
            config: configStore.config,
            sourceProvider: StandardCandidateSources(
                history: HistoryCandidateSource(store: historyStore),
                searchPathProvider: searchPathResolver
            )
        )
        let palette = PaletteAssembly(index: index) { configStore.config.includeFiles }
        let presenter = palette.presenter
        let coordinator = AppCoordinator(
            palette: presenter,
            injector: PanelInjector(prepareForKeyEvents: { [weak presenter] in
                presenter?.releaseKeyForInjection()
            }),
            history: CandidateHistoryRecorder(store: historyStore) { [weak rebuilder] in
                rebuilder?.refreshHistory()
            },
            isAutoConfirmEnabled: { configStore.config.autoConfirm }
        )

        self.configStore = configStore
        self.historyStore = historyStore
        self.rebuilder = rebuilder
        self.palette = palette
        self.coordinator = coordinator
        panelWatcher = PanelWatcher(isAppDisabled: { bundleIdentifier in
            configStore.config.disabledApps.contains(bundleIdentifier)
        })
        globalHotkey = GlobalHotkey { [weak coordinator] in
            coordinator?.handle(.hotkey)
        }
        connectEvents()
        Self.logHistoryLoadResult(historyStore.loadResult)
    }

    /// パレット・パネルの監視と AppCoordinator の間のイベントをつなぐ。
    private func connectEvents() {
        palette.onEvent = { [weak coordinator] event in
            coordinator?.handle(event.coordinatorEvent)
        }
        panelWatcher.onEvent = { [weak coordinator] event in
            coordinator?.handle(event)
        }
        // PanelWatcher は状態の変化を受けた処理の中で同期的にイベントを送らない（Idle へ戻ったときの再走査は非同期）ため、
        // AppCoordinator の「onStateChange の中から handle を同期的に呼ばない」制約を満たす
        coordinator.onStateChange = { [weak panelWatcher] state in
            panelWatcher?.coordinatorStateDidChange(state)
        }
    }

    private static func logHistoryLoadResult(_ result: HistoryLoadResult) {
        guard case .corrupted(let movedTo) = result else { return }
        Log.warning("履歴ファイルを読み込めなかったため、空の履歴で始めます")
        if let movedTo {
            Log.debugPath("読み込めなかった履歴ファイルの退避先", path: movedTo.path(percentEncoded: false))
        }
    }

    // MARK: - メニューの操作

    /// メニューの「候補を再構築」。構築中なら、終わった後に 1 回だけ走査し直す
    func rebuildCandidates() {
        rebuilder.rebuild()
    }

    /// メニューの「履歴をクリア…」。候補の履歴ソースも空にして、クリアした場所が候補に残らないようにする。
    /// - Returns: 空にした履歴をファイルへ保存できたか。
    func clearHistory() -> Bool {
        let isSaved = historyStore.clear()
        rebuilder.historyDidClear()
        return isSaved
    }

    // MARK: - 設定の変更

    private func observeConfigChanges() {
        appliedConfig = configStore.config
        // 購読した時点の設定は流れないため、読み込み済みの設定を反映した直後に同期的に購読する
        let changes = configStore.changes()
        configChangesTask = Task { [weak self] in
            for await config in changes {
                self?.configurationDidChange(config)
            }
        }
    }

    private func configurationDidChange(_ config: Config) {
        Log.debug("設定の変更を反映します")
        let previous = appliedConfig
        appliedConfig = config
        rebuilder.apply(config: config)
        if isHotkeyEnabled {
            registerHotkey(config.hotkey)
        }
        // 最前面のアプリを判定し直し、無効にしたアプリのパネルを閉じる・有効に戻したアプリのパネルを拾う（S-12）
        if previous?.disabledApps != config.disabledApps {
            panelWatcher.disabledAppsDidChange()
        }
    }

    /// 同じホットキーなら何もしない。失敗したら以前のホットキーを維持する（HotkeyRegistrationController）。
    private func registerHotkey(_ hotkey: Hotkey) {
        do {
            if try globalHotkey.update(hotkey) == .registered {
                Log.info("ホットキー \(hotkey) を登録しました")
            }
        } catch {
            let fallback = globalHotkey.activeHotkey.map { "\($0) を維持します" } ?? "パレットの再表示のホットキーは使えません"
            Log.warning("ホットキー \(hotkey) の登録に失敗しました（\(error)）。\(fallback)")
        }
    }
}

extension AppServices: AppLifecycleServices {
    func loadConfiguration() async {
        await configStore.start()
    }

    func startCandidateIndexing() {
        rebuilder.apply(config: configStore.config)
        rebuilder.start()
        observeConfigChanges()
        let presenter = palette.presenter
        rebuildingObservation = ObservationRelay(read: { [rebuilder] in rebuilder.isRebuilding }) { isRebuilding in
            presenter.candidateRebuildingDidChange(isRebuilding)
        }
    }

    func setPanelWatching(_ isActive: Bool) {
        if isActive {
            panelWatcher.start()
            Log.info("パネルの監視を始めました")
        } else {
            panelWatcher.stop()
            Log.info("パネルの監視を止めました")
        }
    }

    func setHotkeyRegistered(_ isRegistered: Bool) {
        isHotkeyEnabled = isRegistered
        if isRegistered {
            registerHotkey(configStore.config.hotkey)
        } else {
            globalHotkey.unregister()
        }
    }

    func shutDown() {
        configChangesTask?.cancel()
        configChangesTask = nil
        rebuildingObservation?.cancel()
        rebuildingObservation = nil
        historyStore.flush()
        rebuilder.stop()
        configStore.stop()
    }
}
