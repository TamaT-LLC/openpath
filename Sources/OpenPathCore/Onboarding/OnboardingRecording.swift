import Foundation

/// 初回起動の案内を終えた（完了・スキップ）かの記録。
@MainActor
public protocol OnboardingRecording {
    var hasFinishedOnboarding: Bool { get }
    func recordOnboardingFinished()
}

/// 案内を終えたかの保存先。UserDefaults がそのまま準拠する。
/// テストで実ユーザーの ~/Library/Preferences にファイルを残さないよう、メモリ上の実装に差し替えられるようにする。
public protocol OnboardingRecordStorage {
    func bool(forKey defaultName: String) -> Bool
    func set(_ value: Bool, forKey defaultName: String)
}

extension UserDefaults: OnboardingRecordStorage {}

/// UserDefaults（`~/Library/Preferences/jp.tamat.openpath.plist`）に記録する。
///
/// 設定ファイル（config.toml）の有無ではなくアプリの状態で判定する。config.toml は dotfiles で別のマシンと共有され得る一方、
/// アクセシビリティ権限はマシンごとに付与するため、設定ファイルがあってもそのマシンで案内を終えたとは限らない。
/// また config.toml は起動のたびに無ければ生成するため、2 回目以降の起動の判定にも使えない。
public struct UserDefaultsOnboardingRecord: OnboardingRecording {
    public static let finishedKey = "onboardingFinished"

    private let storage: any OnboardingRecordStorage

    /// - Parameter storage: 記録先。アプリでは `UserDefaults.standard`
    public init(storage: any OnboardingRecordStorage) {
        self.storage = storage
    }

    public var hasFinishedOnboarding: Bool {
        storage.bool(forKey: Self.finishedKey)
    }

    public func recordOnboardingFinished() {
        storage.set(true, forKey: Self.finishedKey)
    }
}
