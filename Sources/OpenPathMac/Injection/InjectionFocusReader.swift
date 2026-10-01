import ApplicationServices

import OpenPathCore

/// 注入先のアプリのフォーカス中の要素を AX で読み、⌘⇧G の代替（/）を送ってよいかを判断する材料にする。
/// どのロールをファイル一覧・入力欄とみなすかは OpenPathCore の `InjectionFocusedElement.classify` が持つ。
@MainActor
public final class InjectionFocusReader: InjectionFocusReading {
    private let targetProcessID: InjectionTargetProcessID

    /// - Parameter targetProcessID: 注入の最初に記録した注入先のアプリ（`InjectionTargetGuard.targetProcessID`）。
    public init(targetProcessID: @escaping InjectionTargetProcessID) {
        self.targetProcessID = targetProcessID
    }

    public func focusedElement(cutoff: ScanCutoff) async throws -> InjectionFocusedElement {
        guard let processID = targetProcessID() else { return .unavailable }
        return try await onAXQueue { () throws -> InjectionFocusedElement in
            try cutoff.throwIfReached()
            guard let element = FocusedElementAX.focusedElement(ofProcess: processID) else { return .unavailable }
            try cutoff.throwIfReached()
            return InjectionFocusedElement.classify(role: element.role)
        }
    }
}

/// `axQueue` 上で呼ぶ、注入先のアプリのフォーカス中の要素の AX 操作。
enum FocusedElementAX {
    /// processID のアプリのフォーカス中の要素（AXFocusedUIElement）。読めなければ nil。
    /// パネルを別プロセス（openAndSavePanelService）が描く場合、要素はそのプロセスのものとして返る。
    static func focusedElement(ofProcess processID: pid_t) -> AXUIElement? {
        let application = GoToSheetAX.limitingMessagingTimeout(AXUIElementCreateApplication(processID))
        guard let element: AXUIElement = application.attr(kAXFocusedUIElementAttribute) else { return nil }
        return GoToSheetAX.limitingMessagingTimeout(element)
    }

    /// 要素を持つプロセス。AX の往復は伴わない。
    static func processID(of element: AXUIElement) -> pid_t? {
        var processID: pid_t = 0
        guard AXUIElementGetPid(element, &processID) == .success else { return nil }
        return processID
    }
}
