import Foundation

/// 保存先の移動中だけファイル名を保持する。値を履歴やログへ渡さない。
@MainActor
public final class SaveFilenamePreservation {
    public typealias Locate = @MainActor (ScanCutoff) async throws -> (any PanelElementOperating)?
    private let locate: Locate

    public init(locate: @escaping Locate) {
        self.locate = locate
    }

    /// 保存ボタンと同じパネルの名前欄を期限付きで探し、移動前の値を控える。欄や値が無ければ移動を中断する。
    func capture(on timeline: ElapsedTimeline) async throws -> (any PanelElementOperating, String) {
        let field = try await PanelControlOperation.lookUp(
            within: .milliseconds(300), on: timeline, failingAs: .saveFilenameUnavailable
        ) { cutoff in try await self.locate(cutoff) }
        guard let field, let value = try await field.value() else {
            throw InjectionError.saveFilenameUnavailable
        }
        return (field, value)
    }

    /// 同じ注入先が最前面の間だけ、変更された名前を復元する。復元後の値も確認し、不一致は失敗とする。
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
    /// パネルごとに保存/選択ボタンと名前欄を対応付け、一意に決まる欄だけを返す。
    /// 検索欄・一覧内の入力欄・別シートのボタンは除外し、各読み取り前に cutoff を確認する。
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
                if let title = title(element.node)?.trimmingCharacters(in: .whitespacesAndNewlines), (OpenPanelCriteria.saveButtonTitles.contains(title) || OpenPanelCriteria.isConfirmButtonTitle(title)) {
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
