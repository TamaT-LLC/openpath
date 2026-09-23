/// メニューの「ログイン時に起動」を選んだときの処理（FR-CONFIG-03）。
///
/// 現在の状態から登録か解除かを決めて実行し、実行後の状態を読み直して返す。
/// 失敗しても読み直した状態を返すため、呼び出し側はそれをチェックに反映するだけで元の表示に戻せる。
public enum LoginItemToggle {
    public static func perform(using registrar: some LoginItemRegistering) -> LoginItemToggleResult {
        guard let command = registrar.status.toggleCommand else {
            return LoginItemToggleResult(outcome: .unavailable, status: .unavailable)
        }

        let failure: LoginItemError?
        do {
            switch command {
            case .register: try registrar.register()
            case .unregister: try registrar.unregister()
            }
            failure = nil
        } catch {
            failure = LoginItemError(command: command, underlying: error)
        }

        let status = registrar.status
        // システム設定で利用者が無効にしている場合、登録は失敗扱いになることがあるが、許可すれば有効になるため失敗とは伝えない
        if command == .register, status == .requiresApproval {
            registrar.openSystemSettings()
            return LoginItemToggleResult(outcome: .needsApproval, status: status)
        }
        if let failure {
            return LoginItemToggleResult(outcome: .failed(failure), status: status)
        }
        return LoginItemToggleResult(outcome: .completed, status: status)
    }
}

/// `LoginItemToggle.perform(using:)` の結果。
public struct LoginItemToggleResult: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        /// 登録・解除できた
        case completed
        /// 登録したが、システム設定のログイン項目で利用者の許可が必要（設定画面は開いた）
        case needsApproval
        /// 登録・解除に失敗した
        case failed(LoginItemError)
        /// この環境では変更できない（.app バンドル外で実行中）
        case unavailable
    }

    public let outcome: Outcome
    /// 操作後に読み直した登録状態。メニューのチェックにはこれを反映する
    public let status: LoginItemStatus

    public init(outcome: Outcome, status: LoginItemStatus) {
        self.outcome = outcome
        self.status = status
    }
}
