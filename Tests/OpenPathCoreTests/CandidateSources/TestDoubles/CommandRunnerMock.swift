import OpenPathCore

/// 実プロセスを起動せずにコマンド実行を記録・応答する CommandRunning。
/// 応答は呼び出し内容を受け取るハンドラで決めるため、コマンドごとに成功・失敗・待機を切り替えられる。
actor CommandRunnerMock: CommandRunning {
    struct Invocation: Equatable, Sendable {
        let executable: String
        let arguments: [String]
        let environment: [String: String]?
        let timeout: Duration
    }

    /// 想定外のコマンドが実行されたことを示す。
    struct UnexpectedInvocation: Error, Equatable {
        let invocation: Invocation
    }

    typealias Handler = @Sendable (Invocation) async throws -> CommandResult

    private let handler: Handler
    private(set) var invocations: [Invocation] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        timeout: Duration
    ) async throws -> CommandResult {
        let invocation = Invocation(
            executable: executable,
            arguments: arguments,
            environment: environment,
            timeout: timeout
        )
        invocations.append(invocation)
        return try await handler(invocation)
    }
}

extension CommandResult {
    /// 終了コード 0 で指定の標準出力を返す結果。
    static func succeeded(output: String) -> CommandResult {
        CommandResult(exitCode: 0, standardOutput: output, standardError: "")
    }
}
