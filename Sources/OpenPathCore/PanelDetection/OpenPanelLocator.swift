import CoreGraphics

/// トップレベルのウィンドウから NSOpenPanel を探す（DSN-001 §2.2、ARCH-001 §6）。判定結果を要素ごとにキャッシュする。
///
/// 開くパネルと判定したときに、ファイル一覧の先頭の行から選択モードも推定する（DSN-001 §2.3）。
/// 返す `PanelContext.frame` は AX の座標系（左上原点）のまま。NSScreen の座標系への変換は OpenPathMac の PanelScanner で行う。
///
/// ## パネルの候補
/// - ウィンドウ自身: ダイアログ（`runModal` のパネル）か、ウィンドウ一覧に現れたシート
/// - ウィンドウの子のシート: `beginSheetModal` のパネルやサンドボックスアプリのパネル（別プロセスで描画され、ホストの
///   ウィンドウの子の AXSheet として見える）。開くパネルと判定しなかった候補の子のシートも、2 段まで探す
///
/// ## ID の安定性
/// 要素の同一性（Node の `Hashable`。AXUIElement では CFEqual / CFHash）ごとに、開くパネルと判定したときに連番の ID を振る。
/// ⌘⇧G で移動先シートを出したりフォルダを移動したりしても、パネルの要素（ダイアログ・シート）は変わらないため ID も変わらない。
/// ID はハッシュ値から作らないため、ハッシュが衝突しても別のパネルに同じ ID を振ることはない。
///
/// ## キャッシュ
/// - ロール・サブロールは要素ごとに変わらないため、1 度だけ読む
/// - 開くパネルと保存パネルの判定は、要素が破棄される（`forget`）まで覚えておく
/// - 選択モードは、開くパネルと判定したときに推定し、パネルの判定と一緒に覚えておく。⌘⇧G でフォルダを移動しても
///   推定し直さない。行を 1 行も読めなかった場合だけ、判定の再確認と同じ間隔で推定し直す（`SelectionModeState`）
/// - 確定ボタンかファイル一覧が欠けていた候補は、描画途中の可能性があるため間隔を倍々に空けて判定し直し、
///   `OpenPanelCacheConfiguration.maxRechecks` 回で確定する（アラートを 200ms ごとに判定し直さないため）
/// - AX の読み取りに失敗した判定は覚えない。そのウィンドウで直前に見つけたパネルを引き継ぎ、一時的な失敗で消えたとみなさない
/// - 覚えておく要素の数は `capacity` までとし、最後に使ってから長いものから忘れる。
///   ただしパネルの判定と、ウィンドウで直前に見つけたパネルは後回しにする（1 回の走査で容量を超えても ID を保つため）
public struct OpenPanelLocator<Node: Hashable> {
    public let configuration: OpenPanelCacheConfiguration

    /// 覚えている要素の数。
    public var cachedElementCount: Int {
        entries.count
    }

    private var entries: [Node: Entry] = [:]
    /// locate の呼び出しごとに進める。要素を最後に使った時点の記録に使う
    private var tick: UInt64 = 0
    private var nextPanelNumber = 1

    public init(configuration: OpenPanelCacheConfiguration = OpenPanelCacheConfiguration()) {
        self.configuration = configuration
    }

    /// window（`kAXWindowsAttribute` の 1 つ）の中の NSOpenPanel を探す。
    /// - Parameter now: 判定し直すまでの待ち時間を測るための現在時刻。
    public mutating func locate<Reader: PanelTreeReader>(
        in window: Node,
        reader: Reader,
        now: ContinuousClock.Instant
    ) -> OpenPanelLookup<Node> where Reader.Node == Node {
        tick += 1
        touch(window)
        defer { evictIfNeeded() }
        do {
            let panel = try findPanel(in: window, depth: 0, reader: reader, now: now)
            entries[window]?.lastPanel = panel.map {
                LocatedOpenPanel(
                    element: $0.element,
                    context: $0.context,
                    selectionMode: $0.selectionMode,
                    isNewlyClassified: false
                )
            }
            return panel.map(OpenPanelLookup.found) ?? .notFound
        } catch PanelTreeReadError.elementGone {
            forget(window)
            return .notFound
        } catch {
            return .undetermined(lastKnown: entries[window]?.lastPanel)
        }
    }

    /// 要素が破棄された（`kAXUIElementDestroyedNotification`）。覚えている判定結果を捨てる。
    public mutating func forget(_ element: Node) {
        guard let removed = entries.removeValue(forKey: element) else { return }
        guard case .openPanel = removed.verdict else { return }
        // 破棄されたパネルを、読み取りの失敗時に引き継がないようにする
        for (key, entry) in entries where entry.lastPanel?.element == element {
            entries[key]?.lastPanel = nil
        }
    }

    // MARK: - 探索

    /// element（depth 0 はトップレベルのウィンドウ、1 以上はシート）とその子のシートからパネルを探す。
    private mutating func findPanel<Reader: PanelTreeReader>(
        in element: Node,
        depth: Int,
        reader: Reader,
        now: ContinuousClock.Instant
    ) throws -> LocatedOpenPanel<Node>? where Reader.Node == Node {
        // シート（depth 1 以上）は呼び出し側でロールを確かめてある
        let isCandidate = try depth > 0 ? true : isPanelCandidate(element, reader: reader)
        if isCandidate, let panel = try openPanel(element, reader: reader, now: now) {
            return panel
        }
        guard depth < OpenPanelCriteria.maxSheetNestingDepth else { return nil }
        for child in try reader.children(of: element) {
            do {
                guard try role(of: child, reader: reader) == OpenPanelCriteria.sheetRole else { continue }
                if let panel = try findPanel(in: child, depth: depth + 1, reader: reader, now: now) {
                    return panel
                }
            } catch PanelTreeReadError.elementGone {
                // シートが閉じた。ほかの子を調べ続ける
                forget(child)
            }
        }
        return nil
    }

    /// candidate が開くパネルなら、ID・選択モード・矩形を付けて返す。
    private mutating func openPanel<Reader: PanelTreeReader>(
        _ candidate: Node,
        reader: Reader,
        now: ContinuousClock.Instant
    ) throws -> LocatedOpenPanel<Node>? where Reader.Node == Node {
        guard let (id, isNewlyClassified) = try openPanelID(of: candidate, reader: reader, now: now) else { return nil }
        let selectionModeState = entries[candidate]?.selectionMode
        let selectionMode = selectionModeState?.mode ?? .undetermined
        // パネルが動いても最新の位置でパレットを出せるよう、矩形は毎回読む
        let frame = try reader.frame(of: candidate) ?? .zero
        return LocatedOpenPanel(
            element: candidate,
            context: PanelContext(
                id: id,
                isDirectoriesOnly: selectionMode.isDirectoriesOnly,
                frame: frame,
                isSelectionModeProvisional: selectionModeState?.isProvisional ?? false
            ),
            selectionMode: selectionMode,
            isNewlyClassified: isNewlyClassified
        )
    }

    /// candidate が開くパネルならその ID と、この呼び出しで判定したかを返す。キャッシュが有効なら判定しない。
    /// 開くパネルと判定したときに選択モードを推定し、推定し直す予定があれば時刻を見て推定し直す。
    private mutating func openPanelID<Reader: PanelTreeReader>(
        of candidate: Node,
        reader: Reader,
        now: ContinuousClock.Instant
    ) throws -> (PanelContext.ID, isNewlyClassified: Bool)? where Reader.Node == Node {
        touch(candidate)
        var completedRechecks: Int?
        switch entries[candidate]?.verdict {
        case .openPanel(let id):
            entries[candidate]?.selectionMode?.refreshIfDue(reader: reader, now: now, configuration: configuration)
            return (id, false)
        case .rejected:
            return nil
        case .awaitingRecheck(let rechecks, let notBefore):
            guard now >= notBefore else { return nil }
            completedRechecks = rechecks + 1
        case nil:
            break
        }

        let classification = try OpenPanelClassifier.classification(of: candidate, reader: reader)
        switch classification.verdict {
        case .openPanel:
            let id = makePanelID()
            entries[candidate]?.verdict = .openPanel(id)
            entries[candidate]?.selectionMode = SelectionModeState(
                fileList: classification.fileList,
                reader: reader,
                now: now,
                configuration: configuration
            )
            return (id, true)
        case .savePanel:
            entries[candidate]?.verdict = .rejected
        case .missingElements:
            let verdict = verdictAfterMissingElements(completedRechecks: completedRechecks ?? 0, now: now)
            entries[candidate]?.verdict = verdict
        }
        return nil
    }

    private func verdictAfterMissingElements(completedRechecks: Int, now: ContinuousClock.Instant) -> CachedVerdict {
        guard completedRechecks < configuration.maxRechecks else { return .rejected }
        let delay = configuration.recheckDelay(afterRechecks: completedRechecks)
        return .awaitingRecheck(completedRechecks: completedRechecks, notBefore: now.advanced(by: delay))
    }

    private mutating func makePanelID() -> PanelContext.ID {
        defer { nextPanelNumber += 1 }
        return PanelContext.ID(rawValue: "\(OpenPanelCriteria.panelIDPrefix)\(nextPanelNumber)")
    }

    // MARK: - ロール

    private mutating func isPanelCandidate<Reader: PanelTreeReader>(
        _ window: Node,
        reader: Reader
    ) throws -> Bool where Reader.Node == Node {
        let role = try role(of: window, reader: reader)
        if let cached = entries[window]?.subrole {
            return OpenPanelCriteria.isPanelCandidate(role: role, subrole: cached.value)
        }
        let subrole = try reader.subrole(of: window)
        entries[window]?.subrole = CachedAttribute(value: subrole)
        return OpenPanelCriteria.isPanelCandidate(role: role, subrole: subrole)
    }

    private mutating func role<Reader: PanelTreeReader>(
        of element: Node,
        reader: Reader
    ) throws -> String? where Reader.Node == Node {
        touch(element)
        if let cached = entries[element]?.role {
            return cached.value
        }
        let role = try reader.role(of: element)
        entries[element]?.role = CachedAttribute(value: role)
        return role
    }

    // MARK: - 容量

    private mutating func touch(_ element: Node) {
        entries[element, default: Entry(lastUsedTick: tick)].lastUsedTick = tick
    }

    /// 容量を超えていたら、最後に使ってから長い要素から忘れる。今回の locate で使った要素は忘れない
    /// （1 つのウィンドウの子が容量より多い場合に備える）。
    ///
    /// パネルの判定や直前のパネルを持つ要素は、それだけで容量を超えたときに限って忘れる。1 回の走査ではウィンドウごとに
    /// locate が呼ばれるため、ほかのウィンドウの子のロールで容量を超えても、パネルの ID と引き継ぎを失わないようにする。
    /// これらはパネルの数だけあり、通常は破棄の通知（`forget`）で消える。上限は取りこぼし続けた場合の備え。
    private mutating func evictIfNeeded() {
        guard entries.count > configuration.capacity else { return }
        let evictable = entries.filter { $0.value.lastUsedTick < tick }
        let others = evictable.filter { !$0.value.holdsPanel }
        forgetLeastRecentlyUsed(others, count: entries.count - configuration.capacity)

        let panelEntryCount = entries.values.count(where: \.holdsPanel)
        let panelEntries = evictable.filter { $0.value.holdsPanel }
        forgetLeastRecentlyUsed(panelEntries, count: panelEntryCount - configuration.capacity)
    }

    private mutating func forgetLeastRecentlyUsed(_ candidates: [Node: Entry], count: Int) {
        guard count > 0 else { return }
        let victims = candidates
            .sorted { $0.value.lastUsedTick < $1.value.lastUsedTick }
            .prefix(count)
        for victim in victims {
            forget(victim.key)
        }
    }
}

extension OpenPanelLocator {
    /// 要素ごとに覚えておくこと。
    private struct Entry {
        var role: CachedAttribute<String>?
        /// トップレベルのウィンドウでだけ読む
        var subrole: CachedAttribute<String>?
        /// パネルの候補（ダイアログ・シート）でだけ持つ
        var verdict: CachedVerdict?
        /// 開くパネルと判定した候補でだけ持つ
        var selectionMode: SelectionModeState<Node>?
        /// トップレベルのウィンドウで最後に見つけたパネル。読み取りに失敗したときに引き継ぐ
        var lastPanel: LocatedOpenPanel<Node>?
        var lastUsedTick: UInt64

        /// パネルの ID（開くパネルの判定）か、ウィンドウで直前に見つけたパネルを持つか。容量を超えても後回しに忘れる。
        var holdsPanel: Bool {
            if case .openPanel = verdict {
                return true
            }
            return lastPanel != nil
        }

        init(lastUsedTick: UInt64) {
            self.lastUsedTick = lastUsedTick
        }
    }
}

/// 読み取った属性。属性を持たない（nil）ことも覚えておくために包む。
private struct CachedAttribute<Value> {
    let value: Value?
}

/// パネルの候補の判定結果。
private enum CachedVerdict {
    case openPanel(PanelContext.ID)
    /// 開くパネルではないと確定した（保存パネル、または判定し直しても要素が欠けていた）
    case rejected
    /// 要素が欠けていた。notBefore 以降に判定し直す
    case awaitingRecheck(completedRechecks: Int, notBefore: ContinuousClock.Instant)
}
