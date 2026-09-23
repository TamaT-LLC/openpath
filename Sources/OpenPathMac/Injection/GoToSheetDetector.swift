import AppKit
import ApplicationServices

import OpenPathCore

/// ⌘⇧G の移動先シートの出現を AX で判定する（DSN-001 §3.1 ステップ 4）。
///
/// 注入先は最前面アプリのフォーカス中のウィンドウとする。パレットは非アクティブ化パネルのため、
/// 最前面アプリは NSOpenPanel を出しているホストアプリのまま変わらない。
/// 判定条件（どの要素が増えたら出現とみなすか）は OpenPathCore の `GoToSheetScan` が持つ。
@MainActor
public final class GoToSheetDetector: GoToSheetDetecting {
    public typealias FrontmostProcessID = @MainActor () -> pid_t?

    private let frontmostProcessID: FrontmostProcessID

    public init(
        frontmostProcessID: @escaping FrontmostProcessID = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    ) {
        self.frontmostProcessID = frontmostProcessID
    }

    public func makeProbe() async throws -> any GoToSheetProbe {
        guard let processID = frontmostProcessID(), processID != ProcessInfo.processInfo.processIdentifier else {
            // 自分自身へキー入力を送らないよう、注入先のパネルが無いものとして扱う
            throw InjectionError.panelGone
        }
        let (window, baseline) = try await onAXQueue { () throws -> (AXUIElement, GoToSheetScan) in
            let window = try GoToSheetAX.focusedWindow(ofProcess: processID)
            return (window, GoToSheetAX.scan(window))
        }
        return GoToSheetAXProbe(window: window, baseline: baseline)
    }
}

/// ⌘⇧G を送る前に集計した基準と比べて判定する。
@MainActor
private final class GoToSheetAXProbe: GoToSheetProbe {
    private let window: AXUIElement
    private let baseline: GoToSheetScan

    init(window: AXUIElement, baseline: GoToSheetScan) {
        self.window = window
        self.baseline = baseline
    }

    func isSheetShown() async throws -> Bool {
        let window = window
        let current = await onAXQueue { GoToSheetAX.scan(window) }
        return current.indicatesSheetShown(since: baseline)
    }
}

/// `axQueue` 上で呼ぶ AX 操作。
private enum GoToSheetAX {
    static func focusedWindow(ofProcess processID: pid_t) throws -> AXUIElement {
        let application = AXUIElementCreateApplication(processID)
        let value: CFTypeRef
        do {
            value = try application.copyAttributeValue(kAXFocusedWindowAttribute)
        } catch let error as AXElementError {
            throw injectionError(for: error.code)
        }
        guard let window = AXAttributeCast.cast(value, to: AXUIElement.self) else {
            throw InjectionError.axError(code: AXError.failure.rawValue)
        }
        return window
    }

    /// 子の取得に失敗した要素は子なしとして扱う（BoundedBreadthFirstSearch と同じく、判定を止めない）。
    static func scan(_ window: AXUIElement) -> GoToSheetScan {
        GoToSheetScan.scan(
            from: window,
            role: { $0.role },
            children: { $0.children },
            placeholder: { $0.attr(kAXPlaceholderValueAttribute) }
        )
    }

    /// フォーカス中のウィンドウが無い・消えた場合は、パネルが閉じたものとみなす。
    private static func injectionError(for code: AXError) -> InjectionError {
        switch code {
        case .noValue, .invalidUIElement:
            .panelGone
        default:
            .axError(code: code.rawValue)
        }
    }
}
