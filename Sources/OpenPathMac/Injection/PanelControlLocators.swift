import ApplicationServices

import OpenPathCore

/// 注入先のアプリのプロセス ID（`InjectionTargetGuard.targetProcessID`）。
public typealias InjectionTargetProcessID = @MainActor () -> pid_t?

/// 注入先のウィンドウ（`InjectionTargetGuard.targetWindow`）。
public typealias InjectionTargetWindow = @MainActor () -> AXUIElement?

/// 副方式（DSN-001 §3.2）で、移動先シートの入力欄と「移動」/「Go」ボタンを AX で探す。
///
/// 注入の最初に記録したウィンドウ（とそのシート）の中を探す。同じアプリの別のウィンドウの入力欄を書き換えないため。
/// どの要素を入力欄とみなすかは OpenPathCore の `GoToFieldSearch` が持つ。
@MainActor
public final class GoToFieldLocator: GoToFieldLocating {
    private let targetWindow: InjectionTargetWindow

    public init(targetWindow: @escaping InjectionTargetWindow) {
        self.targetWindow = targetWindow
    }

    public func locateGoToField(cutoff: ScanCutoff) async throws -> GoToFieldControls? {
        let window = try PanelControlAX.require(targetWindow())
        let match = try await onAXQueue { () throws -> GoToFieldMatch<AXUIElement>? in
            try GoToFieldSearch.locate(
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
/// 注入の最初に記録したウィンドウ（とそのシート）の中を探す。どのボタンを押すかは OpenPathCore の `OpenButtonSearch` が持つ。
@MainActor
public final class OpenButtonLocator: OpenButtonLocating {
    private let targetWindow: InjectionTargetWindow

    public init(targetWindow: @escaping InjectionTargetWindow) {
        self.targetWindow = targetWindow
    }

    public func locateOpenButton(cutoff: ScanCutoff) async throws -> (any PanelElementOperating)? {
        let window = try PanelControlAX.require(targetWindow())
        let button = try await onAXQueue { () throws -> AXUIElement? in
            try OpenButtonSearch.locate(
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
    static func require(_ window: AXUIElement?) throws -> AXUIElement {
        guard let window else { throw InjectionError.panelGone }
        return window
    }

    /// window（またはそのシート）が、processID のアプリのフォーカス中のウィンドウか。
    /// キー入力はフォーカス中のウィンドウに届くため、同じアプリの別のウィンドウに移っていれば false。
    static func hasFocus(_ window: AXUIElement, inProcess processID: pid_t, cutoff: ScanCutoff) throws -> Bool {
        let focusedWindow: AXUIElement
        do {
            focusedWindow = try GoToSheetAX.focusedWindow(ofProcess: processID)
        } catch InjectionError.panelGone {
            return false
        }
        if CFEqual(focusedWindow, window) {
            return true
        }
        try cutoff.throwIfReached()
        // 移動先シートがウィンドウとしてフォーカスを持つ場合も、記録したウィンドウに付いたものなら注入先とみなす
        guard let parent: AXUIElement = focusedWindow.attr(kAXParentAttribute) else { return false }
        return CFEqual(parent, window)
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
