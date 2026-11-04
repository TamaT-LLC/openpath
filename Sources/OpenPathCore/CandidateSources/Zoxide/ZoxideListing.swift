/// zoxide の履歴一覧を取得できなかった理由。パスを含み得る診断内容は通常ログに出さない。
public enum ZoxideError: Error, Equatable, Sendable {
    case notInstalled(searchPath: String)
    case invalidDataDirectory
    case databaseUnavailable
    case databaseTooLarge
    case launchFailed
    case nonZeroExit(Int32)
    case timedOut
    case cancelled
}

/// CLI が返すディレクトリ一覧。スコアは取り込まず、順位は openpath の履歴で決める。
public struct ZoxideListing: Sendable, Equatable {
    public let directoryPaths: [String]
    public let failure: ZoxideError?

    public init(directoryPaths: [String], failure: ZoxideError? = nil) {
        self.directoryPaths = directoryPaths
        self.failure = failure
    }
}
