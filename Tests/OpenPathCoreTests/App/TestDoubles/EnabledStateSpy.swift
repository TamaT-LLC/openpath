import OpenPathCore

/// メニューの「有効」の記録。起動時に読む値を決められ、記録した値を順に残す。
@MainActor
final class EnabledStateSpy: EnabledStateRecording {
    private(set) var isEnabled: Bool
    private(set) var recorded: [Bool] = []

    /// - Parameter isEnabled: 前回までに記録されていた値
    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    func recordEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        recorded.append(isEnabled)
    }
}

/// メモリ上の「有効」の保存先。実ユーザーの ~/Library/Preferences に触れない。
final class InMemoryEnabledStateStorage: EnabledStateStorage {
    private(set) var values: [String: Bool] = [:]

    func object(forKey defaultName: String) -> Any? {
        values[defaultName]
    }

    func set(_ value: Bool, forKey defaultName: String) {
        values[defaultName] = value
    }
}
