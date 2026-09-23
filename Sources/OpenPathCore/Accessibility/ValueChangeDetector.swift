/// ポーリングで得た値を直前の値と比較し、変化したときだけ報告する。
public struct ValueChangeDetector<Value: Equatable & Sendable>: Sendable {
    /// 最後に観測した値。
    public private(set) var current: Value

    public init(initial: Value) {
        current = initial
    }

    /// 新しい観測値を記録する。
    /// - Returns: 直前の値から変化した場合はその値、変化がなければ nil。
    public mutating func update(_ newValue: Value) -> Value? {
        guard newValue != current else { return nil }
        current = newValue
        return newValue
    }
}
