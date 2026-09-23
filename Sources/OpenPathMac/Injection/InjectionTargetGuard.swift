import AppKit
import ApplicationServices

import OpenPathCore

/// 注入先（注入を始めた時点の最前面アプリと、そのフォーカス中のウィンドウ）を記録し、キー操作・AX 操作の直前ごとに確かめる。
///
/// 確認は、最前面アプリのプロセス ID の比較（NSWorkspace の参照）と、ウィンドウの AXRole の読み取り（AX 1 回）だけの軽いものにする。
/// パネルがホストのウィンドウのシートとして付くアプリ（サンドボックスアプリ等）では、確かめられるのはホストのウィンドウの存在までで、
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
    /// シートの判定と要素探しは、注入中に最前面が変わっても別のアプリを走査しないよう、この注入先に対して行う。
    public var targetProcessID: pid_t? {
        target?.processID
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
        // AX の往復が要らない最前面アプリの確認を先に行う
        guard frontmostProcessID() == target.processID else { return .notFrontmost }
        let window = target.window
        return try await onAXQueue { () throws -> InjectionTargetStatus in
            try cutoff.throwIfReached()
            return try PanelControlAX.exists(window) ? .available : .gone
        }
    }
}
