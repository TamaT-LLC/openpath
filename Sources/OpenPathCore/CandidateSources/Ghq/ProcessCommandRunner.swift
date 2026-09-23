import Foundation

/// `Process` で外部コマンドを実行する CommandRunning。
///
/// - 標準出力と標準エラーは実行中から並行して読み続ける。終了後にまとめて読むと、
///   パイプバッファ（64KiB）を超えた時点で子プロセスの書き込みが詰まり、終了しなくなるため。
/// - 標準入力は空（/dev/null）にする。login shell 等が入力待ちで止まらないようにするため。
/// - タイムアウトやキャンセル時はプロセスに SIGTERM を送り、出力の終端を待たずに戻る。
///   孫プロセスがパイプを握ったまま残ると終端が来ないことがあるため。
public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        timeout: Duration
    ) async throws -> CommandResult {
        let execution = ProcessExecution(executable: executable, arguments: arguments, environment: environment)
        let timeoutTask = Task {
            try await Task.sleep(for: timeout)
            execution.finish(with: .failure(CommandRunnerError.timedOut(executable: executable, timeout: timeout)))
        }
        defer { timeoutTask.cancel() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                execution.start(resumingWith: continuation)
            }
        } onCancel: {
            execution.finish(with: .failure(CancellationError()))
        }
    }
}
