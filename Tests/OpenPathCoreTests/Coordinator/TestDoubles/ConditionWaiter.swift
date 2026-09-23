/// 非同期に進む処理の完了を、条件が満たされるまで待ち合わせる。
/// テストの時間制限でキャンセルされたときも待ちを解き、テスト実行全体が止まらないようにする。
@MainActor
final class ConditionWaiter {
    private struct Waiter {
        let condition: @MainActor () -> Bool
        let continuation: CheckedContinuation<Void, Never>
    }

    private var waiters: [Int: Waiter] = [:]
    private var nextWaiterID = 0

    func wait(until condition: @escaping @MainActor () -> Bool) async {
        guard !condition() else { return }
        let waiterID = nextWaiterID
        nextWaiterID += 1
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters[waiterID] = Waiter(condition: condition, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor in self.resume(waiterID) }
        }
    }

    /// 待ち合わせ対象の状態が変わったときに呼び、条件を満たした待ちを解く。
    func notify() {
        for (waiterID, waiter) in waiters where waiter.condition() {
            resume(waiterID)
        }
    }

    private func resume(_ waiterID: Int) {
        waiters.removeValue(forKey: waiterID)?.continuation.resume()
    }
}
