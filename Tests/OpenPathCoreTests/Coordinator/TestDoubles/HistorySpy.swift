import OpenPathCore

/// HistoryRecording に記録されたパスを保持する。
@MainActor
final class HistorySpy: HistoryRecording {
    private(set) var recordedPaths: [String] = []

    func record(path: String) {
        recordedPaths.append(path)
    }
}

/// 設定値 auto_confirm の差し替え用。confirm 時点の値が読まれることを確かめるため可変にしている。
@MainActor
final class SettingsStub {
    var isAutoConfirmEnabled: Bool

    init(isAutoConfirmEnabled: Bool) {
        self.isAutoConfirmEnabled = isAutoConfirmEnabled
    }
}
