import OpenPathCore

/// SMAppService の代わりに登録状態を持つ偽物。呼び出しを記録する。
final class LoginItemRegistrarFake: LoginItemRegistering {
    enum Call: Equatable {
        case register
        case unregister
        case openSystemSettings
    }

    private(set) var calls: [Call] = []
    private(set) var status: LoginItemStatus

    /// 設定すると `register()` でこのエラーを投げる
    var registerError: (any Error)?
    /// 設定すると `unregister()` でこのエラーを投げる
    var unregisterError: (any Error)?
    /// 登録後（失敗時も含む）の状態。nil なら成功時は `.enabled`、失敗時は変えない
    var statusAfterRegister: LoginItemStatus?
    /// 解除後（失敗時も含む）の状態。nil なら成功時は `.notRegistered`、失敗時は変えない
    var statusAfterUnregister: LoginItemStatus?

    init(status: LoginItemStatus) {
        self.status = status
    }

    func register() throws {
        calls.append(.register)
        try apply(error: registerError, overriddenStatus: statusAfterRegister, successStatus: .enabled)
    }

    func unregister() throws {
        calls.append(.unregister)
        try apply(error: unregisterError, overriddenStatus: statusAfterUnregister, successStatus: .notRegistered)
    }

    func openSystemSettings() {
        calls.append(.openSystemSettings)
    }

    private func apply(error: (any Error)?, overriddenStatus: LoginItemStatus?, successStatus: LoginItemStatus) throws {
        if let overriddenStatus {
            status = overriddenStatus
        }
        if let error {
            throw error
        }
        if overriddenStatus == nil {
            status = successStatus
        }
    }
}
