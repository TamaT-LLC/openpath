import CoreGraphics

import OpenPathCore

/// PanelWatcher のテストで使うアプリとパネル。
enum PanelWatchFixtures {
    static let ownProcessID: Int32 = 100
    static let finderBundleIdentifier = "com.apple.finder"
    static let claudeBundleIdentifier = "com.anthropic.claudefordesktop"
    /// 既定で disabled_apps に入れておく bundle id
    static let disabledBundleIdentifier = "com.example.disabled"
}

extension ActiveApplication {
    static let own = ActiveApplication(processID: PanelWatchFixtures.ownProcessID, bundleIdentifier: AppInfo.bundleIdentifier)
    static let finder = ActiveApplication(processID: 200, bundleIdentifier: PanelWatchFixtures.finderBundleIdentifier)
    static let claude = ActiveApplication(processID: 300, bundleIdentifier: PanelWatchFixtures.claudeBundleIdentifier)
    static let disabled = ActiveApplication(processID: 400, bundleIdentifier: PanelWatchFixtures.disabledBundleIdentifier)
    static let bundleless = ActiveApplication(processID: 500, bundleIdentifier: nil)
}

extension PanelContext {
    static let finderPanel = PanelContext(
        id: PanelContext.ID(rawValue: "finder-open-panel"),
        isDirectoriesOnly: false,
        frame: CGRect(x: 100, y: 100, width: 800, height: 600)
    )

    /// finderPanel と同じパネルがユーザー操作で移動した後の状態
    static let movedFinderPanel = PanelContext(
        id: PanelContext.ID(rawValue: "finder-open-panel"),
        isDirectoriesOnly: false,
        frame: CGRect(x: 140, y: 120, width: 800, height: 600)
    )

    static let claudePanel = PanelContext(
        id: PanelContext.ID(rawValue: "claude-add-folder-panel"),
        isDirectoriesOnly: true,
        frame: CGRect(x: 300, y: 200, width: 700, height: 500)
    )
}

/// 設定 disabled_apps の差し替え用。設定変更を再現するため可変にしている。
final class DisabledAppsStub {
    var bundleIdentifiers: Set<String>

    init(_ bundleIdentifiers: Set<String> = [PanelWatchFixtures.disabledBundleIdentifier]) {
        self.bundleIdentifiers = bundleIdentifiers
    }

    func contains(_ bundleIdentifier: String) -> Bool {
        bundleIdentifiers.contains(bundleIdentifier)
    }
}
