import Carbon.HIToolbox
import CoreGraphics

import OpenPathCore

/// キーイベントを作れなかった。
public struct KeyEventPostingError: Error, Equatable {
    public let keyStroke: InjectionKeyStroke
}

/// キー操作を CGEvent としてシステムへ送る（DSN-001 §3.1）。
///
/// キー入力はその時点のキーウィンドウに届くため、送る前にパレットがキーウィンドウを手放している必要がある
/// （`PathInjectionHooks.prepareForKeyEvents`）。
/// 仮想キーコードは物理キーの位置を表すため、QWERTY 系以外の配列（Dvorak 等）では別のショートカットになる。
@MainActor
public final class KeyboardEventPoster: KeyStrokePosting {
    public init() {}

    public func post(_ keyStroke: InjectionKeyStroke) throws {
        let (keyCode, flags) = Self.keyCombination(for: keyStroke)
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw KeyEventPostingError(keyStroke: keyStroke)
        }
        // ユーザーが押したままの修飾キー（Cmd+Enter で確定した直後の Cmd 等）が混ざらないよう、修飾キーを明示的に上書きする
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private static func keyCombination(for keyStroke: InjectionKeyStroke) -> (CGKeyCode, CGEventFlags) {
        switch keyStroke {
        case .goToFolder:
            (CGKeyCode(kVK_ANSI_G), [.maskCommand, .maskShift])
        case .selectAll:
            (CGKeyCode(kVK_ANSI_A), .maskCommand)
        case .paste:
            (CGKeyCode(kVK_ANSI_V), .maskCommand)
        case .returnKey:
            (CGKeyCode(kVK_Return), [])
        }
    }
}
