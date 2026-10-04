import AppKit
import ApplicationServices

import OpenPathCore

/// 注入先（注入を始めた時点の最前面アプリと、そのフォーカス中のウィンドウ）を記録し、キー操作・AX 操作の直前ごとに確かめる。
///
/// キー入力はその時点のキーウィンドウに届くため、アプリが最前面であることに加えて、フォーカス中のウィンドウが
/// 記録したウィンドウ（またはそのシート）であることを確かめる。同じアプリの別のウィンドウに移っていれば送らない。
/// 確認は、最前面アプリのプロセス ID の比較（NSWorkspace の参照）と、フォーカス中のウィンドウの読み取り（通常は AX 1 回）に留める。
/// 注入の前から移動先シート（⌘⇧G のシート）が開いていると、フォーカス中のウィンドウは移動先シートになる（macOS 27 で確認）。
/// その場合は、シートが付いたパネル（シートの AXParent）を注入先として記録する（Issue #95）。移動先シートを記録すると、
/// 確定でシートが閉じた後に注入先が消えたとみなされ、auto_confirm の「開く」も探せないため。
/// パネルがホストのウィンドウのシートとして付くアプリ（サンドボックスアプリ等）では、記録するのはホストのウィンドウのため、
/// シート（パネル）自体が閉じたことはここでは分からない。
@MainActor
public final class InjectionTargetGuard: InjectionTargetGuarding {
    public typealias FrontmostProcessID = @MainActor () -> pid_t?

    private struct Target {
        let processID: pid_t
        let window: AXUIElement
        let identity: InjectionTargetIdentity
    }

    private let frontmostProcessID: FrontmostProcessID
    private var target: Target?

    public init(
        frontmostProcessID: @escaping FrontmostProcessID = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    ) {
        self.frontmostProcessID = frontmostProcessID
    }

    /// 記録した注入先のプロセス ID。記録前と、記録に失敗した後は nil。
    /// シートの判定は、注入中に最前面が変わっても別のアプリを走査しないよう、この注入先に対して行う。
    public var targetProcessID: pid_t? {
        target?.processID
    }

    /// 記録した注入先のウィンドウ。副方式と auto_confirm の要素探しは、このウィンドウ（とそのシート）の中から行う。
    /// その時点のフォーカス中のウィンドウから探すと、同じアプリの別のウィンドウの要素を操作してしまうおそれがあるため。
    public var targetWindow: AXUIElement? {
        target?.window
    }

    /// 記録した注入先のアプリの識別（bundle id、無ければ pid）。経路の記憶（`GoToSheetRouteMemory`）の鍵にする。
    public var targetIdentity: InjectionTargetIdentity? {
        target?.identity
    }

    public func captureTarget(cutoff: ScanCutoff) async throws {
        target = nil
        guard let processID = frontmostProcessID(), processID != ProcessInfo.processInfo.processIdentifier else {
            // 自分自身へキー入力を送らないよう、注入先のパネルが無いものとして扱う
            throw InjectionError.panelGone
        }
        let (window, isParentOfGoToSheet) = try await onAXQueue { () throws -> (AXUIElement, Bool) in
            try cutoff.throwIfReached()
            let focusedWindow = try GoToSheetAX.focusedWindow(ofProcess: processID)
            // 移動先シートかを確かめられなければ（期限切れ・AX の失敗）、従来どおりフォーカス中のウィンドウを記録する。
            // 確かめるための読み取りで、注入そのものを失敗させないため
            if let panel = try? PanelControlAX.panel(holdingGoToSheet: focusedWindow, cutoff: cutoff) {
                return (panel, true)
            }
            return (focusedWindow, false)
        }
        if isParentOfGoToSheet {
            Log.debug("注入先: 移動先シートが既に開いていたため、そのシートが付いたパネルを注入先にしました")
        }
        let bundleIdentifier = NSRunningApplication(processIdentifier: processID)?.bundleIdentifier
        target = Target(
            processID: processID,
            window: window,
            identity: InjectionTargetIdentity(bundleIdentifier: bundleIdentifier, processID: processID)
        )
    }

    public func currentStatus(cutoff: ScanCutoff) async throws -> InjectionTargetStatus {
        guard let target else { return .gone }
        // AX の往復が要らない最前面アプリの確認を先に行い、切り替わっていれば AX を待たずに打ち切る
        guard frontmostProcessID() == target.processID else { return .notFrontmost }
        let status = try await onAXQueue { () throws -> InjectionTargetStatus in
            try cutoff.throwIfReached()
            if try PanelControlAX.hasFocus(target.window, inProcess: target.processID, cutoff: cutoff) {
                return .available
            }
            try cutoff.throwIfReached()
            // フォーカスが外れた理由が、ウィンドウが閉じたことか、別のウィンドウへ移ったことかを分ける
            return try PanelControlAX.exists(target.window) ? .notFrontmost : .gone
        }
        guard status == .available else { return status }
        // AX の往復（最大でメッセージングタイムアウトまで）の間に切り替わった場合に備え、キー送出の直前にもう一度確かめる
        guard frontmostProcessID() == target.processID else { return .notFrontmost }
        return .available
    }

    /// 注入先のアプリのフォーカス中のウィンドウが移動先シートか（Issue #95）。フォーカス中のウィンドウが無ければ false。
    /// 移動先シートがキーウィンドウなら、フォーカス中のウィンドウは移動先シートそのものになる（macOS 27 の自プロセスのパネルと、
    /// 注入の前から移動先シートが開いていた macOS 26 の VS Code で確認）。
    public func isGoToSheetFocused(cutoff: ScanCutoff) async throws -> Bool {
        guard let target else { return false }
        return try await onAXQueue { () throws -> Bool in
            try cutoff.throwIfReached()
            let focusedWindow: AXUIElement
            do {
                focusedWindow = try GoToSheetAX.focusedWindow(ofProcess: target.processID)
            } catch InjectionError.panelGone {
                return false
            }
            return try GoToSheetIdentity.isGoToSheet(
                focusedWindow,
                cutoff: cutoff,
                role: { $0.role },
                identifier: { $0.attr(kAXIdentifierAttribute) },
                children: PanelControlAX.children(of:)
            )
        }
    }
}
