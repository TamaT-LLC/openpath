import Observation

/// Observable なオブジェクトの値を読み続け、変わるたびに MainActor で `onChange` に渡す。
///
/// `withObservationTracking` の通知は変更の直前（willSet）に 1 度だけ届くため、通知を受けたら MainActor へ戻ってから
/// 読み直し、追跡を張り直す。続けて変わった場合は、読み直した時点の最新の値だけを渡す。
/// 保持している間だけ働くため、呼び出し側で保持すること。
@MainActor
public final class ObservationRelay<Value: Equatable> {
    private let read: @MainActor () -> Value
    private let onChange: @MainActor (Value) -> Void
    /// 最後に渡した値。最初は未送出のため nil
    private var lastValue: Value?
    private var isCancelled = false
    /// 変更の通知から読み直しを呼ぶ窓口。通知のクロージャ（Sendable）がジェネリックな self を捕まえると
    /// Value のメタタイプまで Sendable 性の検査に掛かるため、型パラメータを持たない窓口だけを渡す
    private lazy var retrackTrigger = RetrackTrigger { [weak self] in
        self?.track()
    }

    /// 生成時に現在の値を `onChange` に渡し、以降は値が変わるたびに渡す。
    /// - Parameters:
    ///   - read: 追跡する値の読み方。ここで読んだ Observable なプロパティの変更だけを追う。
    ///   - onChange: 値を受け取る。
    public init(read: @escaping @MainActor () -> Value, onChange: @escaping @MainActor (Value) -> Void) {
        self.read = read
        self.onChange = onChange
        track()
    }

    /// 追跡をやめる。以降は値が変わっても渡さない。
    public func cancel() {
        isCancelled = true
    }

    private func track() {
        guard !isCancelled else { return }
        let value = withObservationTracking {
            read()
        } onChange: { [retrackTrigger] in
            Task { @MainActor in
                retrackTrigger.fire()
            }
        }
        guard value != lastValue else { return }
        lastValue = value
        onChange(value)
    }
}

/// ObservationRelay の読み直しを MainActor で呼ぶ。
@MainActor
private final class RetrackTrigger {
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func fire() {
        action()
    }
}
