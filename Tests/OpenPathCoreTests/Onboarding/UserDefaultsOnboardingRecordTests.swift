import Testing

import OpenPathCore

@MainActor
@Suite("UserDefaultsOnboardingRecord: 初回起動の案内を終えたかの記録")
struct UserDefaultsOnboardingRecordTests {
    @Test("記録が無ければ、案内を終えていない")
    func notFinishedByDefault() {
        let record = UserDefaultsOnboardingRecord(storage: InMemoryRecordStorage())

        #expect(record.hasFinishedOnboarding == false)
    }

    @Test("記録すると、同じ保存先を読む別のインスタンスからも終えたと分かる")
    func recordPersistsInStorage() {
        let storage = InMemoryRecordStorage()
        let record = UserDefaultsOnboardingRecord(storage: storage)

        record.recordOnboardingFinished()

        #expect(record.hasFinishedOnboarding)
        #expect(UserDefaultsOnboardingRecord(storage: storage).hasFinishedOnboarding)
        #expect(storage.values == [UserDefaultsOnboardingRecord.finishedKey: true])
    }
}

/// メモリ上の保存先。実ユーザーの ~/Library/Preferences に触れない。
final class InMemoryRecordStorage: OnboardingRecordStorage {
    private(set) var values: [String: Bool] = [:]

    func bool(forKey defaultName: String) -> Bool {
        values[defaultName] ?? false
    }

    func set(_ value: Bool, forKey defaultName: String) {
        values[defaultName] = value
    }
}
