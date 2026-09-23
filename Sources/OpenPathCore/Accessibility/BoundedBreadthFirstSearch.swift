/// 深さと訪問要素数に上限を設けた幅優先探索。
///
/// AX ツリーの走査は要素ごとにプロセス間の往復が発生し、サンドボックスアプリのパネル
/// （リモート要素）では特に高コストになるため、上限で打ち切って応答時間を抑える（DSN-001 §2.2）。
/// AX から切り離し、ノードの型と子の取得方法を呼び出し側から受け取ることでユニットテスト可能にしている。
public struct BoundedBreadthFirstSearch: Sendable, Equatable {
    /// 既定の最大深さ。起点の直下を深さ 1 と数える。
    public static let defaultMaxDepth = 6
    /// 既定の最大訪問要素数（1 パネルあたり）。
    public static let defaultMaxVisitedNodes = 400

    /// この深さまでの子孫を訪問する。この深さのノードの子は取得しない。
    public let maxDepth: Int
    /// 訪問（条件評価）する子孫の最大数。条件に合わない要素も数える。
    public let maxVisitedNodes: Int

    /// - Parameters:
    ///   - maxDepth: 最大深さ。負の値は 0 として扱う。
    ///   - maxVisitedNodes: 最大訪問要素数。負の値は 0 として扱う。
    public init(maxDepth: Int = defaultMaxDepth, maxVisitedNodes: Int = defaultMaxVisitedNodes) {
        self.maxDepth = max(0, maxDepth)
        self.maxVisitedNodes = max(0, maxVisitedNodes)
    }

    /// 起点を除く子孫を幅優先順に返す。
    /// - Parameters:
    ///   - root: 探索の起点。結果には含めない。
    ///   - children: ノードの子を並び順どおりに返す。
    public func descendants<Node>(
        of root: Node,
        children: (Node) throws -> [Node]
    ) rethrows -> [Node] {
        try descendants(of: root, children: children, where: { _ in true })
    }

    /// 起点を除く子孫のうち、条件に合うものを幅優先順に返す。
    /// 上限に達した時点で打ち切り、それ以降は子の取得も条件の評価も行わない。
    /// - Parameters:
    ///   - root: 探索の起点。結果にも条件評価にも含めない。
    ///   - children: ノードの子を並び順どおりに返す。
    ///   - isIncluded: 結果に含めるかどうか。訪問した子孫ごとに 1 回だけ評価する。
    public func descendants<Node>(
        of root: Node,
        children: (Node) throws -> [Node],
        where isIncluded: (Node) throws -> Bool
    ) rethrows -> [Node] {
        var matches: [Node] = []
        // removeFirst は O(n) のため、配列と先頭位置でキューを表す
        var queue: [(node: Node, depth: Int)] = [(root, 0)]
        var head = queue.startIndex
        var visitedCount = 0

        while head < queue.endIndex, visitedCount < maxVisitedNodes {
            let (node, depth) = queue[head]
            head += 1
            guard depth < maxDepth else { continue }

            let childDepth = depth + 1
            for child in try children(node) {
                guard visitedCount < maxVisitedNodes else { break }
                visitedCount += 1
                if try isIncluded(child) {
                    matches.append(child)
                }
                if childDepth < maxDepth {
                    queue.append((child, childDepth))
                }
            }
        }
        return matches
    }
}
