/// メニューバーの表示を決める入力。StatusItem はこれだけを保持し、表示は `StatusMenuState` で算出する。
public struct StatusMenuInput: Sendable, Equatable {
    /// パネルの検知とパレットの表示を有効にしているか（メニューの「有効」）
    public var isEnabled: Bool
    public var accessibilityPermission: AccessibilityPermissionStatus
    /// 設定ファイルの読み込み・生成の失敗（`ConfigStore.lastError`）
    public var configError: ConfigStoreError?
    public var loginItemStatus: LoginItemStatus

    public init(
        isEnabled: Bool = true,
        accessibilityPermission: AccessibilityPermissionStatus,
        configError: ConfigStoreError? = nil,
        loginItemStatus: LoginItemStatus
    ) {
        self.isEnabled = isEnabled
        self.accessibilityPermission = accessibilityPermission
        self.configError = configError
        self.loginItemStatus = loginItemStatus
    }
}
