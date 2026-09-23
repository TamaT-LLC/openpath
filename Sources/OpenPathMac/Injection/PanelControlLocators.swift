import ApplicationServices

import OpenPathCore

/// 注入先のアプリのプロセス ID（`InjectionTargetGuard.targetProcessID`）。
public typealias InjectionTargetProcessID = @MainActor () -> pid_t?

/// 副方式（DSN-001 §3.2）で、移動先シートの入力欄と「移動」/「Go」ボタンを AX で探す。
///
/// 注入先のアプリのフォーカス中のウィンドウを探し直す（移動先シートが別のウィンドウとして出た場合も拾うため）。
/// どの要素を入力欄とみなすかは OpenPathCore の `GoToFieldSearch` が持つ。
@MainActor
public final class GoToFieldLocator: GoToFieldLocating {
    private let targetProcessID: InjectionTargetProcessID

    public init(targetProcessID: @escaping InjectionTargetProcessID) {
        self.targetProcessID = targetProcessID
    }

    public func locateGoToField(cutoff: ScanCutoff) async throws -> GoToFieldControls? {
        let processID = try PanelControlAX.require(targetProcessID())
        let match = try await onAXQueue { () throws -> GoToFieldMatch<AXUIElement>? in
            try cutoff.throwIfReached()
            let window = try GoToSheetAX.focusedWindow(ofProcess: processID)
            return try GoToFieldSearch.locate(
                in: window,
                cutoff: cutoff,
                role: { $0.role },
                subrole: { $0.subrole },
                title: { $0.title },
                placeholder: { $0.attr(kAXPlaceholderValueAttribute) },
                children: PanelControlAX.children(of:)
            )
        }
        guard let match else { return nil }
        return GoToFieldControls(
            field: AXPanelElement(match.field),
            goButton: match.goButton.map { AXPanelElement($0) }
        )
    }
}

/// auto_confirm（DSN-001 §3.1 ステップ 8）で、パネルの確定ボタン（「開く」等）を AX で探す。
/// どのボタンを押すかは OpenPathCore の `OpenButtonSearch` が持つ。
@MainActor
public final class OpenButtonLocator: OpenButtonLocating {
    private let targetProcessID: InjectionTargetProcessID

    public init(targetProcessID: @escaping InjectionTargetProcessID) {
        self.targetProcessID = targetProcessID
    }

    public func locateOpenButton(cutoff: ScanCutoff) async throws -> (any PanelElementOperating)? {
        let processID = try PanelControlAX.require(targetProcessID())
        let button = try await onAXQueue { () throws -> AXUIElement? in
            try cutoff.throwIfReached()
            let window = try GoToSheetAX.focusedWindow(ofProcess: processID)
            return try OpenButtonSearch.locate(
                in: window,
                cutoff: cutoff,
                role: { $0.role },
                subrole: { $0.subrole },
                title: { $0.title },
                children: PanelControlAX.children(of:)
            )
        }
        return button.map { AXPanelElement($0) }
    }
}

/// AX で操作するパネル内の要素（入力欄・ボタン）。
@MainActor
final class AXPanelElement: PanelElementOperating {
    private let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
    }

    func setValue(_ value: String) async throws {
        let element = element
        try await onAXQueue { () throws in
            try PanelControlAX.check(AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString))
        }
    }

    func press() async throws {
        try await perform(kAXPressAction)
    }

    func confirm() async throws {
        try await perform(kAXConfirmAction)
    }

    func hasDisappeared() async -> Bool {
        let element = element
        return await onAXQueue { () -> Bool in
            // 確かめられなかった（応答が無い等）場合は、消えたとはみなさない
            (try? PanelControlAX.exists(element)) == false
        }
    }

    private func perform(_ action: String) async throws {
        let element = element
        try await onAXQueue { () throws in
            try PanelControlAX.check(AXUIElementPerformAction(element, action as CFString))
        }
    }
}

/// `axQueue` 上で呼ぶ、副方式・auto_confirm・注入先の確認の AX 操作。
enum PanelControlAX {
    /// 注入先を記録していなければ、注入先のパネルが無いものとして扱う。
    static func require(_ processID: pid_t?) throws -> pid_t {
        guard let processID else { throw InjectionError.panelGone }
        return processID
    }

    /// 走査で得た子要素にも、応答しないアプリで止まらないようメッセージングタイムアウトを設定する（GoToSheetDetector と同じ）。
    static func children(of element: AXUIElement) -> [AXUIElement] {
        element.children.map(GoToSheetAX.limitingMessagingTimeout)
    }

    /// 要素がまだ存在するか。
    /// - Throws: 確かめられなければ（応答が無い等）`InjectionError.axError`。
    static func exists(_ element: AXUIElement) throws -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        switch result {
        case .success:
            return true
        case .invalidUIElement:
            return false
        default:
            throw InjectionError.axError(code: result.rawValue)
        }
    }

    /// AX 呼び出しの結果を InjectionError に寄せる。kAXErrorAttributeUnsupported（値を書き込めない）も失敗。
    static func check(_ result: AXError) throws {
        guard result == .success else {
            throw GoToSheetAX.injectionError(for: result)
        }
    }
}
