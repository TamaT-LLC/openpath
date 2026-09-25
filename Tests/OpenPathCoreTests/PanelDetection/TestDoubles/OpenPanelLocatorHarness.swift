import OpenPathCore

/// `OpenPanelLocator` をスタブの AX ツリーと時刻で動かす。
final class OpenPanelLocatorHarness {
    let tree = StubPanelTree()
    var locator: OpenPanelLocator<StubElement>
    /// 経過時間の起点。locate には起点からの経過時間で時刻を渡す
    let start = ContinuousClock.now

    init(configuration: OpenPanelCacheConfiguration = OpenPanelCacheConfiguration()) {
        locator = OpenPanelLocator(configuration: configuration)
    }

    @discardableResult
    func add(_ node: StubNode) -> StubElement {
        tree.add(node)
    }

    func locate(_ window: StubElement, at elapsed: Duration = .zero) -> OpenPanelLookup<StubElement> {
        locator.locate(in: window, reader: tree, now: start.advanced(by: elapsed))
    }

    func panel(in window: StubElement, at elapsed: Duration = .zero) -> LocatedOpenPanel<StubElement>? {
        locate(window, at: elapsed).panel
    }

    /// 診断（debug ログ用）を集めながら探す。
    func locateDiagnosing(
        _ window: StubElement,
        at elapsed: Duration = .zero
    ) -> (lookup: OpenPanelLookup<StubElement>, report: OpenPanelDiagnosticReport) {
        var report = OpenPanelDiagnosticReport()
        let lookup = locator.locate(in: window, reader: tree, now: start.advanced(by: elapsed), diagnostics: &report)
        return (lookup, report)
    }

    /// パネルの候補を判定したか。子のシートを探すときは候補の直下の子（とそのロール）しか読まないため、
    /// それより深い読み取りや、タイトル・説明の読み取りがあれば判定したとみなす。子孫のない候補には使えない。
    func didClassify(_ candidate: StubElement) -> Bool {
        let descendants = tree.descendants(of: candidate)
        return tree.reads.contains { read in
            descendants.contains(read.element) && read.attribute != .role
        }
    }
}
