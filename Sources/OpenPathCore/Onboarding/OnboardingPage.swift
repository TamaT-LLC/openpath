/// 案内のボタン。
public struct OnboardingButton: Sendable, Equatable {
    public let title: String
    public let command: OnboardingCommand

    public init(title: String, command: OnboardingCommand) {
        self.title = title
        self.command = command
    }
}

/// 案内のウインドウに出すページ（UX-001 §7）。Mac 層は表題・本文・ボタンをそのまま並べる。
public enum OnboardingPage: Sendable, Equatable, CaseIterable {
    /// アクセシビリティ権限を何に使うかの説明
    case permissionExplanation
    /// システム設定で許可するのを待っている
    case awaitingPermission
    /// 権限と設定ファイルが揃った。「試してみる」を勧める
    case ready

    /// ウインドウのタイトルバーの文言。どのページでも同じ
    public static let windowTitle = OnboardingText.windowTitle

    public var title: String {
        switch self {
        case .permissionExplanation: OnboardingText.explanationTitle
        case .awaitingPermission: OnboardingText.awaitingTitle
        case .ready: OnboardingText.readyTitle
        }
    }

    /// 本文。1 要素を 1 段落として表示する
    public var messageLines: [String] {
        switch self {
        case .permissionExplanation: OnboardingText.explanationLines
        case .awaitingPermission: OnboardingText.awaitingLines
        case .ready: OnboardingText.readyLines
        }
    }

    /// 既定のボタン（Return で押せる）
    public var primaryButton: OnboardingButton {
        switch self {
        case .permissionExplanation:
            OnboardingButton(title: OnboardingText.openSystemSettings, command: .openSystemSettings)
        case .awaitingPermission:
            OnboardingButton(title: OnboardingText.openSystemSettingsAgain, command: .openSystemSettings)
        case .ready:
            OnboardingButton(title: OnboardingText.tryOpenPanel, command: .tryOpenPanel)
        }
    }

    /// 閉じるボタン（Esc で押せる）
    public var secondaryButton: OnboardingButton {
        switch self {
        case .permissionExplanation, .awaitingPermission:
            OnboardingButton(title: OnboardingText.later, command: .close)
        case .ready:
            OnboardingButton(title: OnboardingText.close, command: .close)
        }
    }
}
