import Foundation

/// メニューの「有効」の記録。再起動後も前回の値で始めるために使う（オーナー判断）。
@MainActor
public protocol EnabledStateRecording {
    /// 記録されている値。記録が無ければ有効（初回の起動は有効で始める）
    var isEnabled: Bool { get }
    func recordEnabled(_ isEnabled: Bool)
}

/// 「有効」の保存先。UserDefaults がそのまま準拠する。
/// テストで実ユーザーの ~/Library/Preferences にファイルを残さないよう、メモリ上の実装に差し替えられるようにする。
public protocol EnabledStateStorage {
    /// 記録が無いことと無効（false）を区別するため、`bool(forKey:)` ではなく値そのものを読む
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Bool, forKey defaultName: String)
}

extension UserDefaults: EnabledStateStorage {}

/// UserDefaults（`~/Library/Preferences/jp.tamat.openpath.plist`）に記録する。
/// 初回起動の案内の記録（`UserDefaultsOnboardingRecord`）と同じ保存先で、キーの書き方も揃える。
public struct UserDefaultsEnabledState: EnabledStateRecording {
    public static let enabledKey = "enabled"
    /// 記録が無いときの値。常駐アプリとして入れた直後から動くよう有効にする
    private static let defaultValue = true

    private let storage: any EnabledStateStorage

    /// - Parameter storage: 記録先。アプリでは `UserDefaults.standard`
    public init(storage: any EnabledStateStorage) {
        self.storage = storage
    }

    public var isEnabled: Bool {
        (storage.object(forKey: Self.enabledKey) as? Bool) ?? Self.defaultValue
    }

    public func recordEnabled(_ isEnabled: Bool) {
        storage.set(isEnabled, forKey: Self.enabledKey)
    }
}
