import Foundation

/// ProcessCommandRunner の 1 回分の実行。
///
/// プロセスの終了・各出力の終端・タイムアウト・キャンセルは別々のスレッドから届くため、
/// 状態はすべて `lock` で保護し、結果の通知（continuation の再開）はどれか 1 つが 1 度だけ行う。
/// `@unchecked Sendable` の根拠: 可変状態はすべて `lock` で保護している。
final class ProcessExecution: @unchecked Sendable {
    private enum State {
        case notStarted
        /// 開始前にタイムアウトやキャンセルで結果が決まった。開始時にそのまま返す。
        case finishedBeforeStart(Result<CommandResult, any Error>)
        case running(CheckedContinuation<CommandResult, any Error>)
        case finished
    }

    private enum OutputStream {
        case standardOutput
        case standardError
    }

    private let lock = NSLock()
    private let executable: String
    private let process = Process()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()

    private var state = State.notStarted
    private var hasLaunched = false
    private var outputData = Data()
    private var errorData = Data()
    private var isOutputOpen = true
    private var isErrorOpen = true
    private var exitCode: Int32?

    init(executable: String, arguments: [String], environment: [String: String]?) {
        self.executable = executable
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe
    }

    /// プロセスを起動し、結果が決まったら continuation を再開する。
    func start(resumingWith continuation: CheckedContinuation<CommandResult, any Error>) {
        let earlyOutcome: Result<CommandResult, any Error>? = lock.withLock {
            if case .finishedBeforeStart(let outcome) = state {
                state = .finished
                return outcome
            }
            state = .running(continuation)
            return nil
        }
        if let earlyOutcome {
            continuation.resume(with: earlyOutcome)
            return
        }
        launch()
    }

    /// 結果を確定する。2 回目以降の呼び出しは無視する。実行中のプロセスがあれば止める。
    func finish(with outcome: Result<CommandResult, any Error>) {
        let continuation: CheckedContinuation<CommandResult, any Error>? = lock.withLock {
            switch state {
            case .notStarted:
                state = .finishedBeforeStart(outcome)
                return nil
            case .running(let continuation):
                state = .finished
                if hasLaunched, process.isRunning {
                    process.terminate()
                }
                return continuation
            case .finishedBeforeStart, .finished:
                return nil
            }
        }
        guard let continuation else { return }
        detachHandlers()
        continuation.resume(with: outcome)
    }

    private func launch() {
        let launchError: (any Error)? = lock.withLock {
            // start とタイムアウト・キャンセルが競合して既に確定していたら、起動しない
            guard case .running = state else { return nil }
            attachHandlers()
            do {
                try process.run()
                hasLaunched = true
                return nil
            } catch {
                return error
            }
        }
        guard let launchError else { return }
        let reason = launchError.localizedDescription
        finish(with: .failure(CommandRunnerError.launchFailed(executable: executable, reason: reason)))
    }

    /// ハンドラは self を強参照するため、結果の確定時に detachHandlers で必ず外すこと。
    private func attachHandlers() {
        outputPipe.fileHandleForReading.readabilityHandler = { [self] handle in
            handleReadable(handle, stream: .standardOutput)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [self] handle in
            handleReadable(handle, stream: .standardError)
        }
        process.terminationHandler = { [self] process in
            handleTermination(exitCode: process.terminationStatus)
        }
    }

    private func detachHandlers() {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
    }

    private func handleReadable(_ handle: FileHandle, stream: OutputStream) {
        let data = handle.availableData
        let isEndOfFile = data.isEmpty
        if isEndOfFile {
            // 終端後も空データで呼ばれ続けるのを防ぐ
            handle.readabilityHandler = nil
        }
        let result: CommandResult? = lock.withLock {
            switch (stream, isEndOfFile) {
            case (.standardOutput, true):
                isOutputOpen = false
            case (.standardOutput, false):
                outputData.append(data)
            case (.standardError, true):
                isErrorOpen = false
            case (.standardError, false):
                errorData.append(data)
            }
            return completedResult()
        }
        if let result {
            finish(with: .success(result))
        }
    }

    private func handleTermination(exitCode: Int32) {
        let result: CommandResult? = lock.withLock {
            self.exitCode = exitCode
            return completedResult()
        }
        if let result {
            finish(with: .success(result))
        }
    }

    /// 終了コードと両方の出力の終端がそろっていれば結果を作る。`lock` を保持した状態で呼ぶこと。
    private func completedResult() -> CommandResult? {
        guard let exitCode, !isOutputOpen, !isErrorOpen else { return nil }
        return CommandResult(
            exitCode: exitCode,
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData, as: UTF8.self)
        )
    }
}
