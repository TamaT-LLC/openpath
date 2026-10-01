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
    private func destinationProcessID(for keyStroke: InjectionKeyStroke) async throws -> Destination {
        guard let target = targetProcessID() else {
            throw KeyEventPostingError(keyStroke: keyStroke)
        }
        let focusedElementOwner = await onAXQueue { () -> pid_t? in
            FocusedElementAX.focusedElement(ofProcess: target).flatMap(FocusedElementAX.processID(of:))
        }
        let processID = InjectionKeyDestination.processID(
            targetProcessID: target,
            focusedElementProcessID: focusedElementOwner,
            ownProcessID: getpid()
        )
        return Destination(processID: processID, targetProcessID: target)
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

    private struct Destination {
        let processID: pid_t
        let targetProcessID: pid_t
    }

    private static func describe(_ destination: Destination?) -> String {
        guard let destination else {
            return "経路: システム（HID）"
        }
        guard destination.processID != destination.targetProcessID else {
            return "経路: 注入先のプロセス（pid \(destination.processID)）"
        }
        return "経路: 注入先のプロセス（フォーカス中の要素の pid \(destination.processID)、注入先のアプリは pid \(destination.targetProcessID)）"
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
