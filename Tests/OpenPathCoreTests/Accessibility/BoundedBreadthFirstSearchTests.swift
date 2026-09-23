import Testing

import OpenPathCore

@Suite("BoundedBreadthFirstSearch")
struct BoundedBreadthFirstSearchTests {
    /// ノード名から子ノード名の一覧を引く隣接リストで木（またはグラフ）を表す。
    private typealias Tree = [String: [String]]

    private struct ChildrenFetchError: Error {}

    /// 子の取得回数を数える。AX では子の取得 1 回が 1 往復に相当するため、打ち切り後に呼ばれないことを検証する。
    private final class ChildrenFetchCounter {
        private let tree: Tree
        private(set) var fetchedNodes: [String] = []

        init(tree: Tree) {
            self.tree = tree
        }

        func children(of node: String) -> [String] {
            fetchedNodes.append(node)
            return tree[node] ?? []
        }
    }

    private static let root = "root"

    /// root から一直線に `length` 階層続く木。深さ n のノード名は "n"。
    private static func chain(length: Int) -> Tree {
        var tree: Tree = [root: ["1"]]
        for depth in 1..<length {
            tree["\(depth)"] = ["\(depth + 1)"]
        }
        return tree
    }

    /// root 直下に `count` 個の葉を持つ木。葉の名前は "0" から始まる連番。
    private static func wide(count: Int) -> Tree {
        [root: (0..<count).map { "\($0)" }]
    }

    // MARK: - 既定値

    @Test("既定の打ち切りは最大 6 階層・最大 400 要素")
    func defaultLimits() {
        let search = BoundedBreadthFirstSearch()

        #expect(BoundedBreadthFirstSearch.defaultMaxDepth == 6)
        #expect(BoundedBreadthFirstSearch.defaultMaxVisitedNodes == 400)
        #expect(search.maxDepth == BoundedBreadthFirstSearch.defaultMaxDepth)
        #expect(search.maxVisitedNodes == BoundedBreadthFirstSearch.defaultMaxVisitedNodes)
    }

    @Test("負の上限は 0 として扱う")
    func negativeLimitsAreClampedToZero() {
        let search = BoundedBreadthFirstSearch(maxDepth: -1, maxVisitedNodes: -1)

        #expect(search.maxDepth == 0)
        #expect(search.maxVisitedNodes == 0)
    }

    // MARK: - 探索順

    @Test("階層順（幅優先）に、各階層内は子の並び順どおりに列挙する")
    func visitsInBreadthFirstOrder() {
        let tree: Tree = [
            Self.root: ["a", "b"],
            "a": ["a1", "a2"],
            "b": ["b1"],
            "a1": ["a1x"],
        ]

        let result = BoundedBreadthFirstSearch().descendants(of: Self.root) { tree[$0] ?? [] }

        #expect(result == ["a", "b", "a1", "a2", "b1", "a1x"])
    }

    @Test("起点ノード自身は結果に含めない")
    func excludesRoot() {
        let result = BoundedBreadthFirstSearch().descendants(of: Self.root) { _ in [] }

        #expect(result.isEmpty)
    }

    @Test("条件に合う子孫だけを探索順で返す")
    func filtersByPredicate() {
        let tree: Tree = [
            Self.root: ["button:1", "group"],
            "group": ["button:2", "text"],
        ]

        let result = BoundedBreadthFirstSearch().descendants(
            of: Self.root,
            children: { tree[$0] ?? [] },
            where: { $0.hasPrefix("button") }
        )

        #expect(result == ["button:1", "button:2"])
    }

    // MARK: - 深さ制限

    @Test("maxDepth より深い子孫は列挙しない")
    func stopsAtMaxDepth() {
        let tree = Self.chain(length: 10)

        let result = BoundedBreadthFirstSearch(maxDepth: 6).descendants(of: Self.root) { tree[$0] ?? [] }

        #expect(result == ["1", "2", "3", "4", "5", "6"])
    }

    @Test("最深階層のノードの子は取得しない")
    func doesNotFetchChildrenAtMaxDepth() {
        let counter = ChildrenFetchCounter(tree: Self.chain(length: 10))

        _ = BoundedBreadthFirstSearch(maxDepth: 3).descendants(of: Self.root, children: counter.children(of:))

        #expect(counter.fetchedNodes == [Self.root, "1", "2"])
    }

    @Test("maxDepth が 1 なら直下の子のみ")
    func maxDepthOneReturnsDirectChildren() {
        let tree: Tree = [Self.root: ["a", "b"], "a": ["a1"]]

        let result = BoundedBreadthFirstSearch(maxDepth: 1).descendants(of: Self.root) { tree[$0] ?? [] }

        #expect(result == ["a", "b"])
    }

    @Test("maxDepth が 0 なら子の取得もせず空を返す")
    func maxDepthZeroReturnsEmpty() {
        let counter = ChildrenFetchCounter(tree: Self.wide(count: 3))

        let result = BoundedBreadthFirstSearch(maxDepth: 0).descendants(of: Self.root, children: counter.children(of:))

        #expect(result.isEmpty)
        #expect(counter.fetchedNodes.isEmpty)
    }

    // MARK: - 要素数制限

    @Test("既定では 400 要素で打ち切る")
    func stopsAtDefaultMaxVisitedNodes() {
        let tree = Self.wide(count: 1_000)

        let result = BoundedBreadthFirstSearch().descendants(of: Self.root) { tree[$0] ?? [] }

        #expect(result.count == BoundedBreadthFirstSearch.defaultMaxVisitedNodes)
        #expect(result.first == "0")
        #expect(result.last == "399")
    }

    @Test("要素数の上限は階層をまたいで数える")
    func countsVisitedNodesAcrossLevels() {
        let tree: Tree = [
            Self.root: ["a", "b", "c"],
            "a": ["a1", "a2", "a3"],
            "b": ["b1"],
        ]

        let result = BoundedBreadthFirstSearch(maxVisitedNodes: 5).descendants(of: Self.root) { tree[$0] ?? [] }

        #expect(result == ["a", "b", "c", "a1", "a2"])
    }

    @Test("条件に合わない要素も上限の要素数に数える")
    func countsNonMatchingNodesTowardLimit() {
        let tree = Self.wide(count: 500)
        var evaluatedCount = 0

        let result = BoundedBreadthFirstSearch().descendants(
            of: Self.root,
            children: { tree[$0] ?? [] },
            where: { node in
                evaluatedCount += 1
                // 401 番目以降にしか一致しないため、上限で打ち切られて何も見つからない
                return (Int(node) ?? 0) >= BoundedBreadthFirstSearch.defaultMaxVisitedNodes
            }
        )

        #expect(result.isEmpty)
        #expect(evaluatedCount == BoundedBreadthFirstSearch.defaultMaxVisitedNodes)
    }

    @Test("上限に達した後は子の取得をしない")
    func doesNotFetchChildrenAfterReachingLimit() {
        let counter = ChildrenFetchCounter(tree: [
            Self.root: ["a", "b"],
            "a": ["a1"],
            "b": ["b1"],
        ])

        let result = BoundedBreadthFirstSearch(maxVisitedNodes: 2).descendants(of: Self.root, children: counter.children(of:))

        #expect(result == ["a", "b"])
        #expect(counter.fetchedNodes == [Self.root])
    }

    @Test("循環があっても上限で停止する")
    func terminatesOnCycle() {
        let tree: Tree = [Self.root: ["a"], "a": ["b"], "b": ["a"]]

        let result = BoundedBreadthFirstSearch(maxDepth: Int.max, maxVisitedNodes: 5).descendants(of: Self.root) { tree[$0] ?? [] }

        #expect(result == ["a", "b", "a", "b", "a"])
    }

    // MARK: - エラー

    @Test("子の取得で投げたエラーは呼び出し元へ伝播する")
    func propagatesChildrenError() {
        #expect(throws: ChildrenFetchError.self) {
            try BoundedBreadthFirstSearch().descendants(of: Self.root) { _ in throw ChildrenFetchError() }
        }
    }
}
