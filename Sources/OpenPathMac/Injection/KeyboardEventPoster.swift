import CoreGraphics
import Darwin

import OpenPathCore

/// キーイベントを作れなかった・送り先を決められなかった。
public struct KeyEventPostingError: Error, Equatable {
    public let keyStroke: InjectionKeyStroke
}

/// キー操作を CGEvent として送る（DSN-001 §3.1）。
///
/// - 経路 `.targetProcess`: 注入先へ `CGEvent.postToPid` で直接送る。物理キーボードと同じ経路（HID）を通らないため、
///   ⌘⇧G をグローバルホットキーにしている他アプリ（Raycast 等）に横取りされない。送り先は、注入先のアプリのフォーカス中の要素を
///   持つプロセスとする（パネルを openAndSavePanelService が描くアプリでは、キー入力を受け取るのはそのプロセスのため）。
///   アプリが前面でなくても届くため、送る前の注入先の確認（`InjectionTargetGuard`）は呼び出し側が必ず行う。
/// - 経路 `.systemWide`: 従来どおり `.cghidEventTap` へ送る。その時点のキーウィンドウに届くが、他アプリのグローバルホットキーに
///   横取りされることがある。注入先のプロセスへ送ったキーでシートが出なかったときの代替（`GoToSheetFallback`）で使う。
/// - 仮想キーコードは、現在の入力ソースのキー配列から目的の文字を入力するキーを求める（Issue #68。Dvorak 等）。
///   求められなければ QWERTY の物理位置で送る。
/// 送り先（AX の読み取り）とキーイベントは `prepare` で決め、送るのは呼び出し側が注入先を確かめた直後の `post()` にする。
/// どちらの経路でも、キー入力を NSOpenPanel に向けるため、パレットはキーウィンドウを手放している必要がある
/// （`PathInjectionHooks.prepareForKeyEvents`）。
@MainActor
public final class KeyboardEventPoster: KeyStrokePosting {
    private let targetProcessID: InjectionTargetProcessID

    /// - Parameter targetProcessID: 注入の最初に記録した注入先のアプリ（`InjectionTargetGuard.targetProcessID`）。
    public init(targetProcessID: @escaping InjectionTargetProcessID) {
        self.targetProcessID = targetProcessID
    }

    /// 送り先を決める AX の読み取りはここで済ませる。呼び出し側は、注入先の確認の直後に待ちを挟まず `post()` で送る。
    public func prepare(_ keyStroke: InjectionKeyStroke, via route: InjectionKeyRoute) async throws -> PreparedKeyStroke {
        let spec = keyStroke.spec
        // 文字に依らないキー（Return）では、キー配列を読まない
        let key = InjectionKeyCodeResolver.resolve(spec, translate: spec.character == nil ? nil : KeyboardLayoutTranslator.current())
        let destination = route == .targetProcess ? try await destinationProcessID(for: keyStroke) : nil
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key.keyCode), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key.keyCode), keyDown: false) else {
            throw KeyEventPostingError(keyStroke: keyStroke)
        }
        // ユーザーが押したままの修飾キー（Cmd+Enter で確定した直後の Cmd 等）が混ざらないよう、修飾キーを明示的に上書きする
        let flags = Self.eventFlags(for: key.modifiers)
        keyDown.flags = flags
        keyUp.flags = flags
        return PreparedKeyStroke {
            if let destination {
                keyDown.postToPid(destination.processID)
                keyUp.postToPid(destination.processID)
            } else {
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }
            Log.debug("キーを送りました（\(keyStroke.logName)、\(Self.describe(destination))、\(Self.describe(key))）")
        }
    }

    /// 送り先のプロセス。注入先のアプリのフォーカス中の要素を持つプロセスを優先し、読めなければ注入先のアプリとする。
    /// debug ログが有効なら、送り先の切り分けのためにフォーカス中の要素のロールとサブロールも読む（Issue #29）。
    private func destinationProcessID(for keyStroke: InjectionKeyStroke) async throws -> Destination {
        guard let target = targetProcessID() else {
            throw KeyEventPostingError(keyStroke: keyStroke)
        }
        let readsRoles = Log.isDebugEnabled
        let focused = await onAXQueue { () -> FocusedElementSummary in
            guard let element = FocusedElementAX.focusedElement(ofProcess: target) else {
                return FocusedElementSummary(processID: nil, role: nil, subrole: nil)
            }
            return FocusedElementSummary(
                processID: FocusedElementAX.processID(of: element),
                role: readsRoles ? element.role : nil,
                subrole: readsRoles ? element.subrole : nil
            )
        }
        let resolution = InjectionKeyDestination.resolve(
            targetProcessID: target,
            focusedElementProcessID: focused.processID,
            ownProcessID: getpid()
        )
        return Destination(resolution: resolution, targetProcessID: target, focused: focused)
    }

    private static func eventFlags(for modifiers: InjectionKeyModifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) {
            flags.insert(.maskCommand)
        }
        if modifiers.contains(.shift) {
            flags.insert(.maskShift)
        }
        return flags
    }

    /// フォーカス中の要素の、送り先の決定と診断に使う属性。ロールとサブロールは debug ログが有効なときだけ読む。
    private struct FocusedElementSummary {
        let processID: pid_t?
        let role: String?
        let subrole: String?
    }

    private struct Destination {
        let resolution: InjectionKeyDestination.Resolution
        let targetProcessID: pid_t
        let focused: FocusedElementSummary

        var processID: pid_t {
            resolution.processID
        }
    }

    /// 送り先の pid がどう決まったか（フォーカス中の要素の pid を読めたか、注入先と同じか、別のプロセスか）と、
    /// フォーカス中の要素のロールを区別して残す（Issue #29: VS Code のリモートのパネルで ⌘⇧G が届かなかった切り分け用）。
    private static func describe(_ destination: Destination?) -> String {
        guard let destination else {
            return "経路: システム（HID）"
        }
        let processID = destination.processID
        let owner: String
        switch destination.resolution.reason {
        case .focusedElementInOtherProcess:
            owner = "フォーカス中の要素の pid \(processID)（別のプロセス）、注入先のアプリは pid \(destination.targetProcessID)"
        case .focusedElementInTarget:
            owner = "pid \(processID)、フォーカス中の要素の pid は注入先のアプリと同じ"
        case .focusedElementUnavailable:
            owner = "pid \(processID)、フォーカス中の要素の pid を読めないため注入先のアプリ"
        case .focusedElementInOwnProcess:
            owner = "pid \(processID)、フォーカス中の要素が openpath 自身のため注入先のアプリ"
        }
        return "経路: 注入先のプロセス（\(owner)、フォーカス中の要素: \(describe(destination.focused))）"
    }

    private static func describe(_ focused: FocusedElementSummary) -> String {
        guard let role = focused.role else {
            return "ロールを読めない"
        }
        guard let subrole = focused.subrole else {
            return role
        }
        return "\(role) / \(subrole)"
    }

    private static func describe(_ key: InjectionResolvedKey) -> String {
        let keyCode = "0x" + String(key.keyCode, radix: 16)
        switch key.source {
        case .layout:
            return "キーコード \(keyCode)（キー配列から）"
        case .physicalPosition:
            return "キーコード \(keyCode)（キー配列から求められないため QWERTY の位置）"
        case .fixed:
            return "キーコード \(keyCode)"
        }
    }
}
