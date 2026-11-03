/// 保存先の移動中だけファイル名を保持する。値を履歴やログへ渡さない。
@MainActor
public final class SaveFilenamePreservation {
    public typealias Locate = @MainActor (ScanCutoff) async throws -> (any PanelElementOperating)?
    private let locate: Locate

    public init(locate: @escaping Locate) {
        self.locate = locate
    }

    func capture(on timeline: ElapsedTimeline) async throws -> (any PanelElementOperating, String) {
        let field = try await PanelControlOperation.lookUp(
            within: .milliseconds(300), on: timeline, failingAs: .saveFilenameUnavailable
        ) { cutoff in try await self.locate(cutoff) }
        guard let field, let value = try await field.value() else {
            throw InjectionError.saveFilenameUnavailable
        }
        return (field, value)
    }

    func restore(_ snapshot: (any PanelElementOperating, String), targetGuard: any InjectionTargetGuarding, on timeline: ElapsedTimeline) async throws {
        try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
        guard try await snapshot.0.value() != snapshot.1 else { return }
        try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
        try await snapshot.0.setValue(snapshot.1)
        guard try await snapshot.0.value() == snapshot.1 else { throw InjectionError.saveFilenameUnavailable }
    }
}

/// 同じパネル内の「保存」ボタンと名前欄を組にして探す。検索欄・移動先シート・一覧内のリネーム欄は選ばない。
public enum SaveFilenameSearch {
    public static func locate<Node>(
        in root: Node,
        cutoff: ScanCutoff = .never,
        role: (Node) -> String?,
        subrole: (Node) -> String?,
        title: (Node) -> String?,
        description: (Node) -> String?,
        identifier: (Node) -> String?,
        children: (Node) -> [Node]
    ) throws -> Node? {
        let elements = try PanelTreeTraversal.elements(
            in: root, search: BoundedBreadthFirstSearch(), cutoff: cutoff,
            role: role, subrole: subrole, identifier: identifier, children: children
        )
        var buttons = Set<Int>()
        var fields: [(Int, Node)] = []
        for element in elements where element.container.isInPanel {
            try cutoff.throwIfReached()
            if element.role == OpenPanelCriteria.buttonRole {
                if let title = title(element.node), (OpenPanelCriteria.saveButtonTitles.contains(title) || OpenPanelCriteria.isConfirmButtonTitle(title)) {
                    buttons.insert(element.container.id)
                }
            } else if element.role == OpenPanelCriteria.textFieldRole {
                guard subrole(element.node) != "AXSearchField" else { continue }
                try cutoff.throwIfReached()
                let label = description(element.node)
                try cutoff.throwIfReached()
                if label.map(OpenPanelCriteria.isSaveFieldLabel) == true || title(element.node).map(OpenPanelCriteria.isSaveFieldLabel) == true {
                    fields.append((element.container.id, element.node))
                }
            }
        }
        let matches = fields.filter { buttons.contains($0.0) }
        return matches.count == 1 ? matches.first?.1 : nil
    }
}
