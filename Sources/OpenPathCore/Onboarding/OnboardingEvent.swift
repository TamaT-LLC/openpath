/// 案内のボタンで選べる操作。
public enum OnboardingCommand: Sendable, Equatable, CaseIterable {
    /// システム設定の「プライバシーとセキュリティ > アクセシビリティ」を開く
    case openSystemSettings
    /// 「開く」ダイアログを出して、パレットを試してもらう
    case tryOpenPanel
    /// 案内を閉じる（「あとで」「閉じる」、ウインドウのクローズボタン、Esc）
    case close
}

/// `OnboardingFlow` への入力。
public enum OnboardingEvent: Sendable, Equatable {
    /// 起動処理を終えた。`hasFinishedBefore` は以前の起動で案内を終えた（完了・スキップ）か
    case launched(hasFinishedBefore: Bool)
    /// メニューの「はじめに…」
    case reopenRequested
    /// アクセシビリティ権限の状態が知らされた
    case permissionChanged(AccessibilityPermissionStatus)
    /// 案内のボタンが選ばれた
    case command(OnboardingCommand)
}

/// `OnboardingFlow` が求める副作用。返した順に実行する。
public enum OnboardingEffect: Sendable, Equatable {
    /// 案内のウインドウにこのページを出して前面に出す（表示中なら内容を差し替える）
    case present(OnboardingPage)
    /// 案内のウインドウを閉じる
    case dismiss
    /// システム設定の「プライバシーとセキュリティ > アクセシビリティ」を開く
    case openAccessibilitySettings
    /// 設定ファイルが無ければ既定値で生成する（既存のファイルは上書きしない）
    case prepareConfigFile
    /// 「開く」ダイアログを出す
    case launchTrialPanel
    /// 案内を終えたことを記録し、次の起動から出さない
    case recordFinished
}
