import OpenPathCore

/// 注入の完了タイミングをテストから制御できる PathInjecting。
@MainActor
final class InjectorFake: PathInjecting {
    enum Behavior {
        /// 呼ばれたら即座に成功する
        case succeed
        /// 呼ばれたら即座に指定のエラーで失敗する
        case fail(any Error)
        /// `resume(callAt:with:)` が呼ばれるまで完了しない。
        /// respondsToCancellation が true なら、キャンセルされた時点で CancellationError を投げて戻る。
        case suspend(respondsToCancellation: Bool)
    }

    struct Call: Equatable {
        let path: String
        let autoConfirm: Bool
    }

    private let behavior: Behavior
    private(set) var calls: [Call] = []
    private(set) var isCancelled = false
    /// 完了待ちの注入。キーは calls のインデックス。
    private var pendingInjections: [Int: CheckedContinuation<Void, any Error>] = [:]
    private let waiter = ConditionWaiter()

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func inject(path: String, autoConfirm: Bool) async throws {
        let callIndex = calls.count
        calls.append(Call(path: path, autoConfirm: autoConfirm))
        waiter.notify()
        switch behavior {
        case .succeed:
            return
        case .fail(let error):
            throw error
        case .suspend(let respondsToCancellation):
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    pendingInjections[callIndex] = continuation
                }
            } onCancel: {
                Task { @MainActor in
                    self.didCancel(callAt: callIndex, resumesInjection: respondsToCancellation)
                }
            }
        }
    }

    /// `.suspend` で止めている注入を完了させる。callIndex は何回目の呼び出しか（0 始まり）。
    func resume(callAt callIndex: Int = 0, with result: Result<Void, any Error>) {
        pendingInjections.removeValue(forKey: callIndex)?.resume(with: result)
    }

    func waitUntilCalled(times: Int = 1) async {
        await waiter.wait { self.calls.count >= times }
    }

    func waitForCancellation() async {
        await waiter.wait { self.isCancelled }
    }

    private func didCancel(callAt callIndex: Int, resumesInjection: Bool) {
        isCancelled = true
        if resumesInjection {
            resume(callAt: callIndex, with: .failure(CancellationError()))
        }
        waiter.notify()
    }
}
