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

    @Test("キーは初回起動の記録（onboardingFinished）と同じ書き方にする")
    func keyName() {
        #expect(UserDefaultsEnabledState.enabledKey == "enabled")
    }
}
