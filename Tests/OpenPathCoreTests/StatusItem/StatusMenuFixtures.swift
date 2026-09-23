import OpenPathCore

/// StatusItem 系テストで共有する入力の組み立て。
enum StatusMenuFixtures {
    static let configFilePath = "/Users/tester/.config/openpath/config.toml"
    static let configError = ConfigStoreError.parseFailed(
        path: configFilePath,
        TOMLParseError(line: 3, column: 5, kind: .missingEqualsSign)
    )

    static func input(
        isEnabled: Bool = true,
        permission: AccessibilityPermissionStatus = .granted,
        configError: ConfigStoreError? = nil,
        loginItemStatus: LoginItemStatus = .notRegistered
    ) -> StatusMenuInput {
        StatusMenuInput(
            isEnabled: isEnabled,
            accessibilityPermission: permission,
            configError: configError,
            loginItemStatus: loginItemStatus
        )
    }

    /// 構成の検査に使う代表的な入力（問題なし・権限なし・設定エラー・両方・無効）
    static let representativeInputs: [StatusMenuInput] = [
        input(),
        input(permission: .notGranted),
        input(configError: configError),
        input(permission: .notGranted, configError: configError),
        input(isEnabled: false, loginItemStatus: .unavailable),
    ]
}
