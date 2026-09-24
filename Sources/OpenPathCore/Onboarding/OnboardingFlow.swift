/// 初回起動の案内の状態遷移（UX-001 §7）。AppKit・UserDefaults から切り離した純粋な状態機械。
///
/// 入力（`OnboardingEvent`）を受けて段階を進め、実行すべき副作用（`OnboardingEffect`）を返す。
/// - 起動時: 以前に案内を終えていなければ出す。権限が既にあれば説明を飛ばし、設定ファイルを用意して完了から出す
/// - 権限の説明 →「システム設定を開く」→ 権限待ち → 権限の付与で設定ファイルを用意して完了
/// - 完了 →「試してみる」で「開く」ダイアログを出す。閉じたら（スキップを含む）終えたことを記録する
/// - メニューの「はじめに…」で、いつでもその時点の権限に合う段階から開き直せる
///
/// 権限の変化は案内を出していない間も受け取り、開き直すときの段階の判断に使う。
public struct OnboardingFlow: Sendable, Equatable {
    public private(set) var step = OnboardingStep.notShown
    /// 案内のウインドウを出しているか
    public private(set) var isPresented = false
    /// 最後に知らされたアクセシビリティ権限の状態
    public private(set) var permission: AccessibilityPermissionStatus

    /// - Parameter permission: 生成時のアクセシビリティ権限の状態
    public init(permission: AccessibilityPermissionStatus) {
        self.permission = permission
    }

    /// 出しているページ。出していなければ nil
    public var presentedPage: OnboardingPage? {
        guard isPresented else { return nil }
        return Self.page(for: step)
    }

    /// 入力を反映し、実行すべき副作用を実行順に返す。
    public mutating func handle(_ event: OnboardingEvent) -> [OnboardingEffect] {
        switch event {
        case .launched(let hasFinishedBefore):
            // メニューから先に開いていた場合は出し直さない
            guard step == .notShown, !hasFinishedBefore else { return [] }
            return begin()
        case .reopenRequested:
            if let presentedPage {
                return [.present(presentedPage)]
            }
            return begin()
        case .permissionChanged(let newPermission):
            return permissionChanged(newPermission)
        case .command(let command):
            guard isPresented else { return [] }
            return perform(command)
        }
    }

    // MARK: - 入力ごとの処理

    /// 権限の有無に合う段階から案内を出す
    private mutating func begin() -> [OnboardingEffect] {
        isPresented = true
        if permission.isGranted {
            return complete()
        }
        step = .explainingPermission
        return [.present(.permissionExplanation)]
    }

    /// 権限がある状態で完了へ進む。設定ファイルは起動時にも生成しているが、その後に消された場合に備えて用意し直す
    private mutating func complete() -> [OnboardingEffect] {
        step = .completed
        return [.prepareConfigFile, .present(.ready)]
    }

    private mutating func permissionChanged(_ newPermission: AccessibilityPermissionStatus) -> [OnboardingEffect] {
        guard newPermission != permission else { return [] }
        permission = newPermission
        guard isPresented else { return [] }
        switch (step, newPermission.isGranted) {
        case (.explainingPermission, true), (.awaitingPermission, true):
            return complete()
        case (.completed, false):
            // 権限が無いと「試してみる」でパネルを検知できないため、説明からやり直す
            step = .explainingPermission
            return [.present(.permissionExplanation)]
        default:
            return []
        }
    }

    private mutating func perform(_ command: OnboardingCommand) -> [OnboardingEffect] {
        switch (command, step) {
        case (.openSystemSettings, .explainingPermission):
            step = .awaitingPermission
            // 案内を権限待ちに替えてから開き、システム設定を前面に残す
            return [.present(.awaitingPermission), .openAccessibilitySettings]
        case (.openSystemSettings, .awaitingPermission):
            return [.openAccessibilitySettings]
        case (.tryOpenPanel, .completed):
            isPresented = false
            // 案内のウインドウが「開く」ダイアログを覆わないよう、先に閉じる
            return [.dismiss, .recordFinished, .launchTrialPanel]
        case (.close, .explainingPermission), (.close, .awaitingPermission):
            step = .skipped
            isPresented = false
            return [.dismiss, .recordFinished]
        case (.close, .completed):
            isPresented = false
            return [.dismiss, .recordFinished]
        default:
            return []
        }
    }

    private static func page(for step: OnboardingStep) -> OnboardingPage? {
        switch step {
        case .explainingPermission: .permissionExplanation
        case .awaitingPermission: .awaitingPermission
        case .completed: .ready
        case .notShown, .skipped: nil
        }
    }
}
