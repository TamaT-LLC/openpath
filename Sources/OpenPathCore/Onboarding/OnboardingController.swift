/// 初回起動の案内の副作用の実行先（実体は OpenPathMac の OnboardingAssembly）。
@MainActor
public protocol OnboardingServices: AnyObject {
    /// 案内のウインドウにページを出して前面に出す。表示中なら内容を差し替える
    func presentOnboarding(_ page: OnboardingPage)
    /// 案内のウインドウを閉じる
    func dismissOnboarding()
    /// システム設定の「プライバシーとセキュリティ > アクセシビリティ」を開く
    func openAccessibilitySettings()
    /// 設定ファイルが無ければ既定値で生成する。完了を待たずに戻ってよい
    func prepareConfigFile()
    /// 「開く」ダイアログを出す
    func launchTrialPanel()
}

/// 初回起動の案内（UX-001 §7）。`OnboardingFlow` の遷移を進め、返った副作用を実行する。
///
/// 起動処理を終えたら `launched()`、メニューの「はじめに…」で `reopen()`、権限の変化で `permissionDidChange(_:)`、
/// 案内のボタンで `perform(_:)` を呼ぶ。案内を終えたか（完了・スキップ）は `OnboardingRecording` に記録し、次の起動から出さない。
@MainActor
public final class OnboardingController {
    public private(set) var flow: OnboardingFlow

    /// 所有者（OnboardingAssembly）が services を兼ねるため、循環参照にならないよう弱参照にする
    private weak var services: (any OnboardingServices)?
    private let record: any OnboardingRecording

    /// - Parameters:
    ///   - services: 副作用の実行先。弱参照で持つため、呼び出し側で保持すること。
    ///   - record: 案内を終えたかの記録。
    ///   - permission: 生成時のアクセシビリティ権限の状態。
    public init(services: any OnboardingServices, record: any OnboardingRecording, permission: AccessibilityPermissionStatus) {
        self.services = services
        self.record = record
        flow = OnboardingFlow(permission: permission)
    }

    /// 起動処理を終えたときに 1 度呼ぶ。以前に案内を終えていなければ出す。
    public func launched() {
        handle(.launched(hasFinishedBefore: record.hasFinishedOnboarding))
    }

    /// メニューの「はじめに…」。表示中なら前面に出し直す。
    public func reopen() {
        handle(.reopenRequested)
    }

    /// アクセシビリティ権限の変化を反映する（`AccessibilityPermissionMonitor.onChange` から呼ぶ）。
    public func permissionDidChange(_ permission: AccessibilityPermissionStatus) {
        handle(.permissionChanged(permission))
    }

    /// 案内のボタンが選ばれた・ウインドウが閉じられたときに呼ぶ。
    public func perform(_ command: OnboardingCommand) {
        handle(.command(command))
    }

    private func handle(_ event: OnboardingEvent) {
        let previousStep = flow.step
        let effects = flow.handle(event)
        if flow.step != previousStep {
            Log.info("初回起動の案内: \(previousStep) → \(flow.step)")
        }
        for effect in effects {
            run(effect)
        }
    }

    private func run(_ effect: OnboardingEffect) {
        switch effect {
        case .present(let page):
            services?.presentOnboarding(page)
        case .dismiss:
            services?.dismissOnboarding()
        case .openAccessibilitySettings:
            services?.openAccessibilitySettings()
        case .prepareConfigFile:
            services?.prepareConfigFile()
        case .launchTrialPanel:
            services?.launchTrialPanel()
        case .recordFinished:
            record.recordOnboardingFinished()
        }
    }
}
