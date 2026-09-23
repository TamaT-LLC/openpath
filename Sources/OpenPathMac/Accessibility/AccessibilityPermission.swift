import AppKit
import ApplicationServices

import OpenPathCore

/// アクセシビリティ権限の確認とシステム設定への誘導（DSN-001 §6）。
/// 要求するのはアクセシビリティのみで、Full Disk Access などは要求しない（NFR-02）。
public enum AccessibilityPermission {
    /// 現在の付与状態を返す。
    /// システムの許可ダイアログは出さない。未付与時の案内はメニューバーから行うため。
    public static func currentStatus() -> AccessibilityPermissionStatus {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AccessibilityPermissionStatus(isTrusted: AXIsProcessTrustedWithOptions(options))
    }

    /// システム設定の「プライバシーとセキュリティ > アクセシビリティ」を開く。
    /// - Returns: 開けた場合は true。
    @MainActor
    @discardableResult
    public static func openSystemSettings(workspace: NSWorkspace = .shared) -> Bool {
        guard let url = AccessibilityPermissionPolicy.systemSettingsURL else { return false }
        return workspace.open(url)
    }
}
