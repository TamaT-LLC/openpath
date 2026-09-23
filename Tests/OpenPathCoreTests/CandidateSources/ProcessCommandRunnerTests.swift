import Foundation
import Testing

import OpenPathCore

/// 実プロセスで ProcessCommandRunner の入出力・タイムアウト・キャンセルを確かめる。
/// ghq や login shell（zsh）は使わず、OS 標準のコマンドだけを起動する。
@Suite("ProcessCommandRunner")
struct ProcessCommandRunnerTests {
    private static let shell = "/bin/sh"
    private static let sleepExecutable = "/bin/sleep"
    private static let catExecutable = "/bin/cat"
    private static let missingExecutable = "/nonexistent/openpath-missing-command"
    private static let longSleepArguments = ["30"]
    private static let generousTimeout: Duration = .seconds(30)
    private static let shortTimeout: Duration = .milliseconds(200)
    /// タイムアウトやキャンセルの後、sleep の完了を待たずに戻ったとみなす上限。
    private static let promptReturnLimit: Duration = .seconds(10)
    /// プロセスを起動し終える程度に待ってからキャンセルするための待ち時間。
    private static let cancellationDelay: Duration = .milliseconds(100)
    /// 止めたプロセスがいなくなったかを確かめる間隔と上限。
    private static let exitPollingInterval: Duration = .milliseconds(20)
    private static let exitPollingLimit: Duration = .seconds(5)
    /// macOS のパイプバッファ（64KiB）を大きく超える量。
    private static let largeOutputByteCount = 1_048_576
    private static let scriptExitCode: Int32 = 3

    private let runner = ProcessCommandRunner()

    @Test("標準出力・標準エラー・終了コードを分けて返す")
    func capturesOutputsAndExitCode() async throws {
        let result = try await runner.run(
            executable: Self.shell,
            arguments: ["-c", "printf out; printf err >&2; exit \(Self.scriptExitCode)"],
            environment: nil,
            timeout: Self.generousTimeout
        )

        #expect(result == CommandResult(exitCode: Self.scriptExitCode, standardOutput: "out", standardError: "err"))
    }

    @Test("environment を指定するとその環境変数で実行する")
    func usesGivenEnvironment() async throws {
        let result = try await runner.run(
            executable: Self.shell,
            arguments: ["-c", "printf %s \"$OPENPATH_TEST_VALUE\""],
            environment: ["OPENPATH_TEST_VALUE": "hello"],
            timeout: Self.generousTimeout
        )

        #expect(result.standardOutput == "hello")
    }

    @Test("標準入力は空にするため、入力を待つコマンドでも止まらない", .timeLimit(.minutes(1)))
    func providesEmptyStandardInput() async throws {
        let result = try await runner.run(
            executable: Self.catExecutable,
            arguments: [],
            environment: nil,
            timeout: Self.generousTimeout
        )

        #expect(result == CommandResult(exitCode: 0, standardOutput: "", standardError: ""))
    }

    @Test("パイプバッファを超える標準出力と標準エラーを書いてもデッドロックしない", .timeLimit(.minutes(1)))
    func handlesOutputLargerThanPipeBuffer() async throws {
        // 標準出力を書き切ってから標準エラーを書く。どちらかを終了後にまとめて読む実装だと書き込みで詰まる
        let byteCount = Self.largeOutputByteCount
        let script = """
            /usr/bin/head -c \(byteCount) /dev/zero | /usr/bin/tr '\\0' o
            /usr/bin/head -c \(byteCount) /dev/zero | /usr/bin/tr '\\0' e >&2
            """

        let result = try await runner.run(
            executable: Self.shell,
            arguments: ["-c", script],
            environment: nil,
            timeout: Self.generousTimeout
        )

        #expect(result.exitCode == 0)
        #expect(result.standardOutput.utf8.count == byteCount)
        #expect(result.standardError.utf8.count == byteCount)
        #expect(result.standardOutput.allSatisfy { $0 == "o" })
        #expect(result.standardError.allSatisfy { $0 == "e" })
    }

    @Test("タイムアウトを超えると完了を待たずに timedOut を投げる", .timeLimit(.minutes(1)))
    func throwsTimedOut() async throws {
        let clock = ContinuousClock()
        let start = clock.now

        let error = await #expect(throws: CommandRunnerError.self) {
            try await runner.run(
                executable: Self.sleepExecutable,
                arguments: Self.longSleepArguments,
                environment: nil,
                timeout: Self.shortTimeout
            )
        }

        #expect(error == .timedOut(executable: Self.sleepExecutable, timeout: Self.shortTimeout))
        #expect(clock.now - start < Self.promptReturnLimit)
    }

    @Test("タイムアウトしたプロセスは終了させる", .timeLimit(.minutes(1)))
    func terminatesTimedOutProcess() async throws {
        let pidFile = FileManager.default.temporaryDirectory
            .appending(path: "openpath-runner-tests-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: pidFile) }

        await #expect(throws: CommandRunnerError.self) {
            try await runner.run(
                executable: Self.shell,
                arguments: ["-c", "echo $$ > '\(pidFile.path)'; exec \(Self.sleepExecutable) \(Self.longSleepArguments[0])"],
                environment: nil,
                timeout: Self.shortTimeout
            )
        }

        let pidText = try String(contentsOf: pidFile, encoding: .utf8)
        let pid = try #require(pid_t(pidText.trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(await Self.waitUntilProcessExits(pid))
    }

    @Test("存在しない実行ファイルは launchFailed を投げる")
    func throwsLaunchFailedForMissingExecutable() async throws {
        let error = await #expect(throws: CommandRunnerError.self) {
            try await runner.run(
                executable: Self.missingExecutable,
                arguments: [],
                environment: nil,
                timeout: Self.generousTimeout
            )
        }

        guard case .launchFailed(let executable, _) = try #require(error) else {
            Issue.record("launchFailed ではない: \(String(describing: error))")
            return
        }
        #expect(executable == Self.missingExecutable)
    }

    @Test("呼び出し元がキャンセルされると完了を待たずに CancellationError を投げる", .timeLimit(.minutes(1)))
    func throwsCancellationError() async throws {
        let runner = runner
        let task = Task {
            try await runner.run(
                executable: Self.sleepExecutable,
                arguments: Self.longSleepArguments,
                environment: nil,
                timeout: Self.generousTimeout
            )
        }
        try await Task.sleep(for: Self.cancellationDelay)
        let clock = ContinuousClock()
        let start = clock.now

        task.cancel()
        let result = await task.result

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(clock.now - start < Self.promptReturnLimit)
    }

    @Test("起動前にキャンセル済みならプロセスを起動せず CancellationError を投げる")
    func throwsCancellationErrorWhenAlreadyCancelled() async {
        let runner = runner
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await runner.run(
                executable: Self.sleepExecutable,
                arguments: Self.longSleepArguments,
                environment: nil,
                timeout: Self.generousTimeout
            )
        }

        let result = await task.result

        #expect(throws: CancellationError.self) { try result.get() }
    }

    /// 指定の pid のプロセスが存在しなくなるまで待つ。上限までに消えなければ false。
    private static func waitUntilProcessExits(_ pid: pid_t) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + exitPollingLimit
        while clock.now < deadline {
            if kill(pid, 0) != 0, errno == ESRCH {
                return true
            }
            try? await Task.sleep(for: exitPollingInterval)
        }
        return false
    }
}
