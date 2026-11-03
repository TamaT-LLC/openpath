import Foundation

/// 保存先の絶対パスを読み直し、移動先と一致した場合だけ成功にする。
/// シートの閉鎖やローカライズされた表示名は、移動成功の根拠にしない。
@MainActor
public final class SaveDestinationVerification {
    public typealias ReadPath = @MainActor (ScanCutoff) async throws -> String?
    private let readPath: ReadPath
    private let clock: any Clock<Duration>

    /// - Parameter readPath: 記録済みの保存パネルの現在地。絶対パスを特定できなければ nil を返す。
    public init(clock: any Clock<Duration> = ContinuousClock(), readPath: @escaping ReadPath) {
        self.clock = clock
        self.readPath = readPath
    }

    /// 表示の更新を最大 300ms 待つ。不一致・読み取り不能・期限切れは成功にせず、呼び出し側で履歴記録を止める。
    /// 注入先が変わった場合やキャンセルは、再試行せず元の失敗を返す。
    func verify(path: String, targetGuard: any InjectionTargetGuarding) async throws {
        let expected = Self.canonicalDirectory(path)
        let timeline = ElapsedTimeline(clock: self.clock)
        let deadline: Duration = .milliseconds(300)
        while timeline.elapsed < deadline {
            try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
            let actual: String?
            let readDeadline = min(deadline, timeline.elapsed + .milliseconds(100))
            do {
                let observed = try await withScanCutoff(
                    at: readDeadline, on: timeline,
                    readPath
                )
                guard timeline.elapsed < readDeadline else { throw ScanCutoff.Reached() }
                actual = observed
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                actual = nil
            }
            try Task.checkCancellation()
            if let actual, let expected, Self.canonicalDirectory(actual) == expected {
                try await InjectionTargetCheck.ensureAvailable(targetGuard, on: timeline)
                try Task.checkCancellation()
                guard timeline.elapsed < deadline else { throw InjectionError.saveNavigationUnverified }
                return
            }
            guard timeline.elapsed + .milliseconds(50) < deadline else { break }
            try await timeline.sleep(untilElapsed: timeline.elapsed + .milliseconds(50))
        }
        throw InjectionError.saveNavigationUnverified
    }

    /// 相対パスや表示名は拒否する。/var と /private/var、シンボリックリンク経由の同じディレクトリは同一視する。
    private static func canonicalDirectory(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
