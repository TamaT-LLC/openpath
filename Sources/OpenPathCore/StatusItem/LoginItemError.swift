import Foundation

/// ログイン時に起動の登録・解除に失敗した理由。
public struct LoginItemError: Error, Sendable, Equatable {
    public let command: LoginItemCommand
    /// 元のエラーのドメインとコード。ログにはこちらだけを記録する
    public let domain: String
    public let code: Int
    /// 利用者に見せる理由（元のエラーの localizedDescription）
    public let reason: String

    public init(command: LoginItemCommand, underlying: any Error) {
        let nsError = underlying as NSError
        self.command = command
        domain = nsError.domain
        code = nsError.code
        reason = nsError.localizedDescription
    }

    /// ログ用の要約。localizedDescription はパスを含み得るため入れない（NFR-05）
    public var logSummary: String {
        "\(command.logName) \(domain) \(code)"
    }
}

extension LoginItemError: CustomStringConvertible {
    /// ダイアログに出す説明
    public var description: String {
        switch command {
        case .register: "ログイン時に起動を有効にできませんでした（\(reason)）"
        case .unregister: "ログイン時に起動を無効にできませんでした（\(reason)）"
        }
    }
}

private extension LoginItemCommand {
    var logName: String {
        switch self {
        case .register: "register"
        case .unregister: "unregister"
        }
    }
}
