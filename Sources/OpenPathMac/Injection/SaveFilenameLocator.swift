import ApplicationServices
import OpenPathCore

@MainActor
enum SaveFilenameLocator {
    /// 記録済みの注入先を AX キューで調べ、名前欄だけを操作アダプタとして返す。見つからなければ nil。
    static func locate(in window: AXUIElement?, cutoff: ScanCutoff) async throws -> (any PanelElementOperating)? {
        let window = try PanelControlAX.require(window)
        let field = try await onAXQueue {
            try SaveFilenameSearch.locate(
                in: window, cutoff: cutoff,
                role: { $0.role }, subrole: { $0.subrole }, title: { $0.title },
                description: { $0.attr(kAXDescriptionAttribute) },
                identifier: { $0.attr(kAXIdentifierAttribute) }, children: PanelControlAX.children(of:)
            )
        }
        return field.map { AXPanelElement($0) }
    }
}
