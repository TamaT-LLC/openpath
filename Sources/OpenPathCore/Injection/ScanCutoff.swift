/// AX の走査を途中で打ち切る条件（期限の到来、または注入の Task のキャンセル）。
///
/// AX の呼び出しは同期で、呼び出し元の Task をキャンセルしても走査は止まらない。応答の遅いアプリで走査が長引くと、
/// AppCoordinator が注入を取り消した後も `InjectionSerialGate` が次の注入を待たせ続けるため、要素ごとの AX 操作の前にこれを確かめる。
/// 走査は `axQueue` 上で行うため、どのスレッドからでも確かめられるようにしている。
public struct ScanCutoff: Sendable {
    /// 打ち切り条件に達したため走査をやめた。
    public struct Reached: Error, Equatable {
        public init() {}
    }

    /// 打ち切らない。
    public static let never = ScanCutoff { false }

    private let checkReached: @Sendable () -> Bool

    public init(isReached: @escaping @Sendable () -> Bool) {
        checkReached = isReached
    }

    public var isReached: Bool {
        checkReached()
    }

    /// - Throws: 打ち切り条件に達していれば `Reached`。
    public func throwIfReached() throws {
        if isReached {
            throw Reached()
        }
    }
}
