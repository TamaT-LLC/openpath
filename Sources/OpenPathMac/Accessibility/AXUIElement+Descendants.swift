import ApplicationServices

import OpenPathCore

/// 子孫の探索。幅優先で最大 `maxDepth` 階層・最大 400 要素で打ち切る（DSN-001 §2.2）。
/// 訪問した要素ごとに AX の呼び出しが発生するため `axQueue` 上で呼ぶこと。
extension AXUIElement {
    /// 条件に合う子孫を幅優先順に返す。
    /// 複数の条件を調べる場合は、ロール別に何度も探索するよりこちらで 1 回にまとめると AX の呼び出しを減らせる。
    public func descendants(
        maxDepth: Int = BoundedBreadthFirstSearch.defaultMaxDepth,
        where isIncluded: (AXUIElement) -> Bool
    ) -> [AXUIElement] {
        BoundedBreadthFirstSearch(maxDepth: maxDepth).descendants(
            of: self,
            children: { $0.children },
            where: isIncluded
        )
    }

    /// 指定したロールの子孫を幅優先順に返す。
    public func descendants(role: String, maxDepth: Int = BoundedBreadthFirstSearch.defaultMaxDepth) -> [AXUIElement] {
        descendants(roles: [role], maxDepth: maxDepth)
    }

    /// 指定したロールのいずれかに一致する子孫を幅優先順に返す。
    public func descendants(roles: Set<String>, maxDepth: Int = BoundedBreadthFirstSearch.defaultMaxDepth) -> [AXUIElement] {
        descendants(maxDepth: maxDepth) { element in
            guard let role = element.role else { return false }
            return roles.contains(role)
        }
    }
}
