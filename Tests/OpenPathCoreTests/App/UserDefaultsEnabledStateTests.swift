import Testing

import OpenPathCore

@MainActor
@Suite("UserDefaultsEnabledState: メニューの「有効」の記録")
struct UserDefaultsEnabledStateTests {
    @Test("記録が無ければ有効（初回の起動は有効で始める）")
    func enabledByDefault() {
        let state = UserDefaultsEnabledState(storage: InMemoryEnabledStateStorage())

        #expect(state.isEnabled)
    }

    @Test("無効を記録すると、同じ保存先を読む別のインスタンスからも無効と分かる")
    func recordsDisabled() {
        let storage = InMemoryEnabledStateStorage()
        let state = UserDefaultsEnabledState(storage: storage)

        state.recordEnabled(false)

        #expect(state.isEnabled == false)
        #expect(UserDefaultsEnabledState(storage: storage).isEnabled == false)
        #expect(storage.values == [UserDefaultsEnabledState.enabledKey: false])
    }

    @Test("有効に戻すと、有効として記録する")
    func recordsEnabledAgain() {
        let storage = InMemoryEnabledStateStorage()
        let state = UserDefaultsEnabledState(storage: storage)
        state.recordEnabled(false)

        state.recordEnabled(true)

        #expect(UserDefaultsEnabledState(storage: storage).isEnabled)
        #expect(storage.values == [UserDefaultsEnabledState.enabledKey: true])
    }

    @Test("真偽値以外で記録された値（defaults write -string NO や起動引数 -enabled NO）も、UserDefaults の真偽値の解釈で読む")
    func readsNonBooleanValueAsUserDefaultsBool() {
        let state = UserDefaultsEnabledState(storage: StringValuedStorage(value: "NO", boolValue: false))

        #expect(state.isEnabled == false)
    }

    @Test("キーは初回起動の記録（onboardingFinished）と同じ書き方にする")
    func keyName() {
        #expect(UserDefaultsEnabledState.enabledKey == "enabled")
    }
}

/// 文字列で記録された値を返す保存先。UserDefaults は "NO" などの文字列も `bool(forKey:)` で真偽値として読む。
private struct StringValuedStorage: EnabledStateStorage {
    let value: String
    /// UserDefaults が value を真偽値として解釈した結果
    let boolValue: Bool

    func object(forKey defaultName: String) -> Any? {
        value
    }

    func bool(forKey defaultName: String) -> Bool {
        boolValue
    }

    func set(_ value: Bool, forKey defaultName: String) {}
}
