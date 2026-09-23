import AppKit
import ApplicationServices

import OpenPathCore

/// 注入先（注入を始めた時点の最前面アプリと、そのフォーカス中のウィンドウ）を記録し、キー操作・AX 操作の直前ごとに確かめる。
///
/// キー入力はその時点のキーウィンドウに届くため、アプリが最前面であることに加えて、フォーカス中のウィンドウが
/// 記録したウィンドウ（またはそのシート）であることを確かめる。同じアプリの別のウィンドウに移っていれば送らない。
/// 確認は、最前面アプリのプロセス ID の比較（NSWorkspace の参照）と、フォーカス中のウィンドウの読み取り（通常は AX 1 回）に留める。
/// パネルがホストのウィンドウのシートとして付くアプリ（サンドボックスアプリ等）では、記録するのはホストのウィンドウのため、
/// シート（パネル）自体が閉じたことはここでは分からない。
@MainActor
public final class InjectionTargetGuard: InjectionTargetGuarding {
    public typealias FrontmostProcessID = @MainActor () -> pid_t?

    private struct Target {
        let processID: pid_t
        let window: AXUIElement
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

    public func captureTarget(cutoff: ScanCutoff) async throws {
        target = nil
        guard let processID = frontmostProcessID(), processID != ProcessInfo.processInfo.processIdentifier else {
            // 自分自身へキー入力を送らないよう、注入先のパネルが無いものとして扱う
            throw InjectionError.panelGone
        }
        let window = try await onAXQueue { () throws -> AXUIElement in
            try cutoff.throwIfReached()
            return try GoToSheetAX.focusedWindow(ofProcess: processID)
        }
        target = Target(processID: processID, window: window)
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
}
