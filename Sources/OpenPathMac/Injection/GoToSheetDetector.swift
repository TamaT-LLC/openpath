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

    public func makeProbe(cutoff: ScanCutoff) async throws -> any GoToSheetProbe {
        guard let processID = frontmostProcessID(), processID != ProcessInfo.processInfo.processIdentifier else {
            // 自分自身へキー入力を送らないよう、注入先のパネルが無いものとして扱う
            throw InjectionError.panelGone
        }
        let (window, baseline) = try await onAXQueue { () throws -> (AXUIElement, GoToSheetScan) in
            let window = try GoToSheetAX.focusedWindow(ofProcess: processID)
            return (window, try GoToSheetAX.scan(window, cutoff: cutoff))
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

    func isSheetShown(cutoff: ScanCutoff) async throws -> Bool {
        let window = window
        let current = try await onAXQueue { () throws -> GoToSheetScan in
            try GoToSheetAX.scan(window, cutoff: cutoff)
        }
        return current.indicatesSheetShown(since: baseline)
    }
}

/// `axQueue` 上で呼ぶ AX 操作。
enum GoToSheetAX {
    /// 1 回の AX 呼び出しを待つ上限（秒）。
    /// 応答しないアプリで既定（約 6 秒）まで止まると、AppCoordinator がキャンセルした後も注入の後始末と次の注入が待たされるため短くする。
    /// タイムアウトは要素の参照ごとの設定で子要素には引き継がれないため、走査で得た要素にもそれぞれ設定する。
    private static let messagingTimeoutSeconds: Float = 0.25

    static func focusedWindow(ofProcess processID: pid_t) throws -> AXUIElement {
        let application = limitingMessagingTimeout(AXUIElementCreateApplication(processID))
        let value: CFTypeRef
        do {
            value = try application.copyAttributeValue(kAXFocusedWindowAttribute)
        } catch let error as AXElementError {
            throw injectionError(for: error.code)
        }
        guard let window = AXAttributeCast.cast(value, to: AXUIElement.self) else {
            throw InjectionError.axError(code: AXError.failure.rawValue)
        }
        return limitingMessagingTimeout(window)
    }

    /// 子の取得に失敗した要素（タイムアウトを含む）は子なしとして扱う（BoundedBreadthFirstSearch と同じく、判定を止めない）。
    /// 走査全体の長さは cutoff（シート待ちの期限と注入のキャンセル）で抑える。
    static func scan(_ window: AXUIElement, cutoff: ScanCutoff) throws -> GoToSheetScan {
        try GoToSheetScan.scan(
            from: window,
            cutoff: cutoff,
            role: { $0.role },
            children: { $0.children.map(limitingMessagingTimeout) },
            placeholder: { $0.attr(kAXPlaceholderValueAttribute) }
        )
    }

    /// 設定はプロセス内で完結し AX の往復を伴わないため、要素ごとに設定しても走査のコストは増えない。
    static func limitingMessagingTimeout(_ element: AXUIElement) -> AXUIElement {
        _ = AXUIElementSetMessagingTimeout(element, messagingTimeoutSeconds)
        return element
    }

    /// フォーカス中のウィンドウが無い・消えた場合は、パネルが閉じたものとみなす。
    static func injectionError(for code: AXError) -> InjectionError {
        switch code {
        case .noValue, .invalidUIElement:
            .panelGone
        default:
            .axError(code: code.rawValue)
        }
    }
}
