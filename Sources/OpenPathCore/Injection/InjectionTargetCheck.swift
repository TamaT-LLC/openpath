/// 注入先の記録と確認を、期限とキャンセルで打ち切りつつ行い、結果を InjectionError に寄せる。
@MainActor
enum InjectionTargetCheck {
    /// 記録・確認 1 回の上限。NSWorkspace の参照と AX の軽い呼び出しだけなので、長引くのは応答しないアプリに限られる。
    static let timeLimit: Duration = .milliseconds(100)

    /// 最前面アプリとそのウィンドウを注入先として記録する。
    static func capture(_ targetGuard: any InjectionTargetGuarding, on timeline: ElapsedTimeline) async throws {
        try Task.checkCancellation()
        do {
            try await withScanCutoff(at: timeline.elapsed + timeLimit, on: timeline) { cutoff in
                try await targetGuard.captureTarget(cutoff: cutoff)
            }
        } catch {
            throw injectionError(from: error)
        }
    }

    /// 注入先がまだ有効でなければ投げる。キー操作とパネルへの AX 操作の直前ごとに呼ぶ。
    /// - Throws: 最前面でなければ `.targetNotFrontmost`、ウィンドウが消えていれば `.panelGone`。
    ///   確かめられなければ `.axError`（期限切れは cannotComplete）、キャンセル時は `CancellationError`。
    static func ensureAvailable(_ targetGuard: any InjectionTargetGuarding, on timeline: ElapsedTimeline) async throws {
        try Task.checkCancellation()
        let status: InjectionTargetStatus
        do {
            status = try await withScanCutoff(at: timeline.elapsed + timeLimit, on: timeline) { cutoff in
                try await targetGuard.currentStatus(cutoff: cutoff)
            }
        } catch {
            throw injectionError(from: error)
        }
        switch status {
        case .available:
            return
        case .notFrontmost:
            throw InjectionError.targetNotFrontmost
        case .gone:
            throw InjectionError.panelGone
        }
    }

    /// 確かめられなかった場合は、別のアプリへ送ってしまうおそれがあるため、送らずに AX の失敗として扱う。
    private static func injectionError(from error: any Error) -> any Error {
        if error is InjectionError || error is CancellationError {
            return error
        }
        if error is ScanCutoff.Reached {
            return Task.isCancelled ? CancellationError() : InjectionError.axError(code: InjectionAXErrorCode.cannotComplete)
        }
        return InjectionError.axError(code: InjectionAXErrorCode.failure)
    }
}

/// パネル内の要素（入力欄・ボタン）の探索と操作の共通処理。
@MainActor
enum PanelControlOperation {
    /// 要素を探す走査を、期限とキャンセルで打ち切りつつ行う。
    /// - Parameters:
    ///   - cutOffError: 期限で打ち切ったとき・InjectionError 以外で失敗したときに投げるエラー。
    static func lookUp<T>(
        within limit: Duration,
        on timeline: ElapsedTimeline,
        failingAs cutOffError: InjectionError,
        _ operation: (ScanCutoff) async throws -> T
    ) async throws -> T {
        do {
            return try await withScanCutoff(at: timeline.elapsed + limit, on: timeline, operation)
        } catch {
            if error is InjectionError || error is CancellationError {
                throw error
            }
            if error is ScanCutoff.Reached, Task.isCancelled {
                throw CancellationError()
            }
            throw cutOffError
        }
    }

    /// 値のセット。押下と違い要素が閉じる理由が無いため、要素が消えていれば失敗とする。
    static func setValue(_ value: String, on element: any PanelElementOperating) async throws {
        do {
            try await element.setValue(value)
        } catch {
            throw injectionError(from: error)
        }
    }

    /// 要素を確定させる操作。
    enum Activation {
        /// AXPress（ボタン）
        case press
        /// kAXConfirmAction（入力欄）
        case confirm
    }

    /// 押下・確定。操作でシートやパネルが閉じると、AX が失敗を返すことがある（要素が消えた、閉じる処理で応答が遅れた）。
    /// 失敗しても要素が消えていれば、操作は届いて閉じたものとみなす。
    static func activate(_ element: any PanelElementOperating, by activation: Activation) async throws {
        do {
            switch activation {
            case .press:
                try await element.press()
            case .confirm:
                try await element.confirm()
            }
        } catch {
            guard await element.hasDisappeared() else {
                throw injectionError(from: error)
            }
        }
    }

    /// アダプタは InjectionError を投げる約束だが、それ以外は AX の失敗として扱う。
    private static func injectionError(from error: any Error) -> any Error {
        if error is InjectionError || error is CancellationError {
            return error
        }
        return InjectionError.axError(code: InjectionAXErrorCode.failure)
    }
}
