/// `OpenPanelLocator` が要素ごとに覚えておくこと（判定のキャッシュ）。OpenPanelLocator の中でだけ使う。
extension OpenPanelLocator {
    /// 要素ごとに覚えておくこと。
    struct Entry {
        var role: CachedAttribute<String>?
        /// トップレベルのウィンドウでだけ読む
        var subrole: CachedAttribute<String>?
        /// トップレベルのウィンドウで、ロール・サブロールで候補にならないときだけ読む（診断中は候補でも読む）
        var identifier: CachedAttribute<String>?
        /// 候補でないウィンドウとして診断を記録したか。初めて見たときだけ記録する
        var isNonCandidateReported = false
        /// パネルの候補（ダイアログ・シート・AXIdentifier が open-panel のウィンドウ）でだけ持つ
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

/// 診断で、判定した候補を表すための組。
struct CandidateDiagnosticTarget {
    let target: OpenPanelDiagnostic.Target
    let reason: PanelCandidateReason
}

/// 読み取った属性。属性を持たない（nil）ことも覚えておくために包む。
struct CachedAttribute<Value> {
    let value: Value?
}

/// パネルの候補の判定結果。
enum CachedVerdict {
    case openPanel(PanelContext.ID)
    /// 開くパネルではないと確定した（保存パネル、または判定し直しても要素が欠けていた）
    case rejected
    /// 要素が欠けていた。notBefore 以降に判定し直す
    case awaitingRecheck(completedRechecks: Int, notBefore: ContinuousClock.Instant)

    var isAwaitingRecheck: Bool {
        if case .awaitingRecheck = self {
            return true
        }
        return false
    }
}
