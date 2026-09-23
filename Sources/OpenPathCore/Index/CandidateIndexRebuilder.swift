import Observation

/// 候補ソースを起動時・一定間隔（既定 5 分）・手動・設定の変更で走査し直し、CandidateIndex に反映する
/// （FR-SOURCE-04、FR-CONFIG-02、DSN-002 §3）。
///
/// 並行性:
/// - 状態は MainActor で管理し、走査は再構築 1 回ごとに `Task.detached(priority: .utility)` の中で行う。
///   ソースごとの走査はその子タスクで並行させ、走査を終えたソースから `CandidateIndex.replace(source:with:)` で
///   差し替える。差し替えはロック下の入れ替えなので、走査中のクエリは直前の候補で答える（TST-001 §2.4）。
/// - 再構築は同時に 1 回しか走らせない。CandidateIndex は同じソースの並行した差し替えを後勝ちにするため、
///   こうして同じソースの走査と差し替えを直列にする。
/// - 再構築中に届いた契機は重ねて走らせず、終わった後に 1 回だけまとめて走査し直す。
///   設定の変更は走査中の結果を古くするため、走査を取り消してから新しい設定で走査し直す。
/// - 周期の再構築は、再構築を終えてから `interval` 後に行う。走査中には周期の契機を積まない。
@MainActor
@Observable
public final class CandidateIndexRebuilder {
    /// 周期の再構築の既定の間隔（FR-SOURCE-04「既定 5 分」）
    public nonisolated static let defaultInterval: Duration = .seconds(5 * 60)

    private enum Lifecycle {
        case idle
        case running
        /// 終了処理後。再開はしない
        case stopped
    }

    private struct ActiveCycle {
        let scope: CandidateRebuildScope
        let task: Task<Void, Never>
    }

    /// 候補ソースを全件走査し直している最中か（フッターの「候補を構築中…」用。UX-001 §5）。
    /// 後続の再構築が控えている間も true のまま。履歴だけの取り直し（`refreshHistory()`）では true にしない。
    public private(set) var isRebuilding = false
    /// 各ソースの直近の収集で出た警告（ソースの並び順）。取り消した走査のソースは直前の警告のまま
    public private(set) var warnings: [CandidateSourceWarning] = []

    private let index: CandidateIndex
    private let sourceProvider: any CandidateSourceProviding
    private let interval: Duration
    /// `clock` という名前は Foundation 経由で見える Darwin の `clock()` と紛らわしいため避ける
    private let scheduleClock: any Clock<Duration>
    @ObservationIgnored private var config: Config
    @ObservationIgnored private var lifecycle = Lifecycle.idle
    @ObservationIgnored private var activeCycle: ActiveCycle?
    /// 再構築中に届いた契機をまとめた、次に行う再構築
    @ObservationIgnored private var pendingScope: CandidateRebuildScope?
    @ObservationIgnored private var periodicTask: Task<Void, Never>?
    /// 候補をインデックスに入れた可能性のあるソース。設定から外れたソースの候補を取り除くのに使う
    @ObservationIgnored private var managedKinds: Set<CandidateSourceKind> = []
    /// 直近の全件の再構築でのソースの並び。警告の並びに使う
    @ObservationIgnored private var sourceOrder: [CandidateSourceKind] = []
    @ObservationIgnored private var warningsBySource: [CandidateSourceKind: [CandidateSourceWarning]] = [:]
    @ObservationIgnored private var idleWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    @ObservationIgnored private var nextIdleWaiterID = 0

    /// - Parameters:
    ///   - index: 候補の反映先。
    ///   - config: 起動時の設定。以降の変更は `apply(config:)` で渡す。
    ///   - sourceProvider: 設定から候補ソースを組み立てる。本番では `StandardCandidateSources` を渡す。
    ///   - interval: 周期の再構築の間隔。
    ///   - clock: 周期の計測に使う。テストでは手動で進める Clock を渡す。
    public init(
        index: CandidateIndex,
        config: Config,
        sourceProvider: any CandidateSourceProviding,
        interval: Duration = defaultInterval,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.index = index
        self.config = config
        self.sourceProvider = sourceProvider
        self.interval = interval
        scheduleClock = clock
    }

    // MARK: - 契機

    /// 起動時の再構築を始め、以降は一定間隔で再構築する。2 回目以降と `stop()` の後は何もしない
    public func start() {
        guard lifecycle == .idle else { return }
        lifecycle = .running
        Log.debug("候補の構築を始めます")
        request(.all)
    }

    /// 全ソースを走査し直す（メニューの「候補を再構築」。FR-CONFIG-02）。
    /// 再構築中なら重ねて走らせず、終わった後に 1 回だけ走査し直す。
    public func rebuild() {
        request(.all)
    }

    /// 確定履歴だけを取り直す。確定を記録するたびに呼ぶ（DSN-002 §3）。
    /// 再構築中なら、終わった後に取り直す。
    public func refreshHistory() {
        request(.history)
    }

    /// 設定の変更を反映する。`start()` の前に呼んだ場合は起動時の再構築に使う。
    ///
    /// 候補ソースに関わる設定（roots / depth / include_files / ignore / ghq.enabled）が変わったときだけ、
    /// 走査中の再構築を取り消して新しい設定で全ソースを走査し直す。roots から外したルートと、
    /// 無効にした ghq の候補は取り除く。取り除くまでの間も、クエリには直前の候補で答える。
    public func apply(config newConfig: Config) {
        guard lifecycle != .stopped else { return }
        let changesSources = CandidateSourceSettings(newConfig) != CandidateSourceSettings(config)
        config = newConfig
        guard changesSources, lifecycle == .running else { return }
        Log.info("設定の変更に合わせて候補を再構築します")
        request(.all, cancellingActive: true)
    }

    /// 走査を取り消し、以降の再構築をすべて止める。アプリの終了時に呼ぶ。
    /// 取り消した走査の結果では差し替えない。以降 `start()` しても再開しない。
    public func stop() {
        guard lifecycle != .stopped else { return }
        lifecycle = .stopped
        periodicTask?.cancel()
        periodicTask = nil
        pendingScope = nil
        activeCycle?.task.cancel()
        updateIsRebuilding()
        if activeCycle == nil {
            resumeIdleWaiters()
        }
    }

    /// 進行中の再構築と、後続の再構築がすべて終わるまで待つ。
    func waitUntilIdle() async {
        guard activeCycle != nil || pendingScope != nil else { return }
        let waiterID = nextIdleWaiterID
        nextIdleWaiterID += 1
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                idleWaiters[waiterID] = continuation
            }
        } onCancel: {
            Task { @MainActor in
                self.idleWaiters.removeValue(forKey: waiterID)?.resume()
            }
        }
    }

    // MARK: - 再構築の実行

    private func request(_ scope: CandidateRebuildScope, cancellingActive: Bool = false) {
        guard lifecycle == .running else { return }
        guard let activeCycle else {
            startCycle(scope)
            return
        }
        pendingScope = pendingScope?.merged(with: scope) ?? scope
        if cancellingActive {
            activeCycle.task.cancel()
        }
        updateIsRebuilding()
    }

    private func startCycle(_ scope: CandidateRebuildScope) {
        periodicTask?.cancel()
        periodicTask = nil
        let (sources, staleKinds) = plan(scope)
        let task = Task.detached(priority: .utility) { [weak self, index] in
            let outcome = await CandidateRebuildCycle.run(sources: sources, removing: staleKinds, in: index)
            await self?.finishCycle(outcome)
        }
        activeCycle = ActiveCycle(scope: scope, task: task)
        updateIsRebuilding()
    }

    /// 走査するソースと、取り除くソースを決める。全件の再構築では、設定から外れたソースを取り除く対象にする
    private func plan(_ scope: CandidateRebuildScope) -> (sources: [any CandidateSource], staleKinds: Set<CandidateSourceKind>) {
        var seenKinds: Set<CandidateSourceKind> = []
        // 同じ kind のソースを並行して走査すると差し替えが後勝ちになるため、重複は先勝ちで除く
        let sources = sourceProvider.sources(for: config).filter { seenKinds.insert($0.kind).inserted }
        switch scope {
        case .history:
            return (sources.filter { $0.kind == .history }, [])
        case .all:
            let kinds = sources.map(\.kind)
            let staleKinds = managedKinds.subtracting(kinds)
            managedKinds = Set(kinds)
            sourceOrder = kinds
            return (sources, staleKinds)
        }
    }

    private func finishCycle(_ outcome: CandidateRebuildOutcome) {
        activeCycle = nil
        record(outcome)
        if lifecycle == .running, let next = pendingScope {
            pendingScope = nil
            startCycle(next)
            return
        }
        updateIsRebuilding()
        if lifecycle == .running {
            schedulePeriodicRebuild()
        }
        resumeIdleWaiters()
    }

    private func schedulePeriodicRebuild() {
        periodicTask?.cancel()
        periodicTask = Task { [weak self, scheduleClock, interval] in
            do {
                try await scheduleClock.sleep(for: interval)
            } catch {
                return
            }
            // 待ちを終えた後に他の契機で再構築が始まっていれば、重ねて積まない
            guard !Task.isCancelled else { return }
            self?.periodicRebuildIsDue()
        }
    }

    private func periodicRebuildIsDue() {
        periodicTask = nil
        Log.debug("定期の候補の再構築を始めます")
        request(.all)
    }

    // MARK: - 結果の反映

    private func record(_ outcome: CandidateRebuildOutcome) {
        for kind in outcome.removed {
            warningsBySource[kind] = nil
        }
        for kind in sourceOrder {
            guard let current = outcome.replaced[kind] else { continue }
            let previous = warningsBySource[kind] ?? []
            for log in CandidateSourceWarningLog.logs(for: current, previous: previous) {
                log.emit()
            }
            warningsBySource[kind] = current.isEmpty ? nil : current
        }
        for (kind, errorType) in outcome.failed {
            Log.warning("候補ソース（\(kind.logLabel)）の収集に失敗しました（\(errorType)）")
            if let path = kind.logPath {
                Log.debugPath("収集に失敗した候補のルート", path: path)
            }
        }
        Log.debug(
            "候補の再構築を終えました（差し替え \(outcome.replaced.count)、取り消し \(outcome.cancelled.count)、"
                + "失敗 \(outcome.failed.count)、除去 \(outcome.removed.count)、\(outcome.elapsed)）"
        )
        let latestWarnings = sourceOrder.flatMap { warningsBySource[$0] ?? [] }
        if warnings != latestWarnings {
            warnings = latestWarnings
        }
    }

    private func updateIsRebuilding() {
        let isFullRebuildQueued = activeCycle?.scope == .all || pendingScope == .all
        let newValue = lifecycle == .running && isFullRebuildQueued
        if isRebuilding != newValue {
            isRebuilding = newValue
        }
    }

    private func resumeIdleWaiters() {
        let waiters = idleWaiters.values
        idleWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

/// 設定のうち、候補ソースの組み立てに関わる値。これが変わったときだけ再構築する
private struct CandidateSourceSettings: Equatable {
    let roots: [String]
    let depth: Int
    let includeFiles: Bool
    let ignore: [String]
    let isGhqEnabled: Bool

    init(_ config: Config) {
        roots = config.roots
        depth = config.depth
        includeFiles = config.includeFiles
        ignore = config.ignore
        isGhqEnabled = config.ghq.enabled
    }
}
