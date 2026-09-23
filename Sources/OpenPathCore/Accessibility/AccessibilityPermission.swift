import Foundation

/// アクセシビリティ権限の付与状態。
public enum AccessibilityPermissionStatus: Sendable, Equatable {
    case granted
    case notGranted

    /// `AXIsProcessTrusted` 系 API の戻り値から変換する。
    public init(isTrusted: Bool) {
        self = isTrusted ? .granted : .notGranted
    }

    public var isGranted: Bool {
        self == .granted
    }
}

/// アクセシビリティ権限の扱いに関する取り決め（DSN-001 §6, ARCH-001 §9）。
/// openpath が要求する権限はアクセシビリティのみ（NFR-02）。
public enum AccessibilityPermissionPolicy {
    /// 権限の変化を確認する間隔。付与直後に自動で有効化するため、5 秒以内に検知できる間隔にする。
    public static let pollingInterval: Duration = .seconds(5)

    /// システム設定の「プライバシーとセキュリティ > アクセシビリティ」を開く URL。
    public static let systemSettingsURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    public static var systemSettingsURL: URL? {
        URL(string: systemSettingsURLString)
    }
}
