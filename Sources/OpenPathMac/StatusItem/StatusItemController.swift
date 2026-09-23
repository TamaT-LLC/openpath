import AppKit

import OpenPathCore

/// メニューバーの常駐アイコンとメニュー（UX-001 §5, §6, FR-CONFIG-02/03）。
///
/// 表示内容（バッジ・ツールチップ・項目の並びと状態）は OpenPathCore の `StatusMenuState` が決め、
/// ここでは NSStatusItem / NSMenu への反映と、StatusItem 自身が受け持つ操作
/// （設定ファイルを開く・履歴クリアの確認・ログイン時に起動・終了）だけを行う。
/// 候補の再構築や履歴のクリアなど他のモジュールに属する操作は `StatusMenuActions` で外から注入する。
///
/// 権限と設定エラーは呼び出し側が `setAccessibilityPermission(_:)` / `setConfigError(_:)` で知らせる。
/// ログイン時に起動の状態はシステム設定でも変わるため、メニューを開くたびに読み直す。
@MainActor
public final class StatusItemController: NSObject {
    /// 現在の表示内容
    public private(set) var state: StatusMenuState

    /// 「有効」のチェック。ここで変えても `StatusMenuActions.setEnabled` は呼ばない（呼び出し側からの反映用）
    public var isEnabled: Bool {
        get { input.isEnabled }
        set { input.isEnabled = newValue }
    }

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let actions: StatusMenuActions
    private let loginItem: any LoginItemRegistering
    private let configFileOpener: ConfigFileOpener
    private var input: StatusMenuInput {
        didSet {
            guard input != oldValue else { return }
            apply(StatusMenuState(input))
        }
    }

    /// - Parameters:
    ///   - configFileURL: 「設定ファイルを開く…」で開くファイル。nil なら既定の場所（`~/.config/openpath/config.toml`）
    ///   - defaultConfigContents: 設定ファイルが無いときに作り直す内容。nil なら ghq root を含まない既定の内容
    ///   - loginItem: ログイン時に起動の登録先
    ///   - actions: 他のモジュールに属する操作の実行先
    ///   - isEnabled: 「有効」の初期値
    ///   - accessibilityPermission: 権限の初期値。nil なら生成時に確認する
    public init(
        statusBar: NSStatusBar = .system,
        configFileURL: URL? = nil,
        defaultConfigContents: (() -> String)? = nil,
        loginItem: any LoginItemRegistering = SMAppServiceLoginItem(),
        actions: StatusMenuActions = StatusMenuActions(),
        isEnabled: Bool = true,
        accessibilityPermission: AccessibilityPermissionStatus? = nil
    ) {
        let homeDirectory = NSHomeDirectory()
        let input = StatusMenuInput(
            isEnabled: isEnabled,
            accessibilityPermission: accessibilityPermission ?? AccessibilityPermission.currentStatus(),
            loginItemStatus: loginItem.status
        )
        self.input = input
        state = StatusMenuState(input)
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        self.actions = actions
        self.loginItem = loginItem
        configFileOpener = ConfigFileOpener(
            fileURL: configFileURL ?? Self.defaultConfigFileURL(homeDirectory: homeDirectory),
            defaultContents: defaultConfigContents ?? { DefaultConfigFile.contents(ghqRoot: nil, homeDirectory: homeDirectory) },
            workspace: .shared
        )
        super.init()

        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        apply(state)
    }

    // MARK: - 状態の反映

    /// アクセシビリティ権限の変化を反映する（`AccessibilityPermissionMonitor.onChange` から呼ぶ）
    public func setAccessibilityPermission(_ status: AccessibilityPermissionStatus) {
        input.accessibilityPermission = status
    }

    /// 設定ファイルの読み込みエラーを反映する（`ConfigStore.lastError` の変化で呼ぶ）
    public func setConfigError(_ error: ConfigStoreError?) {
        input.configError = error
    }

    /// ログイン時に起動の状態を読み直す
    public func refreshLoginItemStatus() {
        input.loginItemStatus = loginItem.status
    }

    private func apply(_ newState: StatusMenuState) {
        state = newState
        updateButton()
        let renderer = StatusMenuRenderer(target: self, action: #selector(menuItemSelected(_:))) { [actions] command in
            actions.canPerform(command)
        }
        renderer.render(newState, into: menu)
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        if let image = StatusItemIcon.image(for: state.icon) {
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = AppInfo.name
        }
        button.appearsDisabled = state.icon.isDimmed
        button.toolTip = state.toolTip
        button.setAccessibilityLabel(state.icon.accessibilityLabel)
    }

    // MARK: - 操作

    @objc private func menuItemSelected(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? StatusMenuCommand else { return }
        perform(command)
    }

    private func perform(_ command: StatusMenuCommand) {
        switch command {
        case .toggleEnabled:
            toggleEnabled()
        case .rebuildCandidates:
            Log.info("メニューから候補の再構築を選択しました")
            actions.rebuildCandidates?()
        case .openConfigFile:
            configFileOpener.open { dialog in
                StatusItemAlert.run(dialog)
            }
        case .clearHistory:
            confirmClearHistory()
        case .toggleLaunchAtLogin:
            toggleLaunchAtLogin()
        case .openAccessibilitySettings:
            actions.openAccessibilitySettings()
        case .quit:
            actions.quit()
        }
    }

    private func toggleEnabled() {
        guard let setEnabled = actions.setEnabled else { return }
        let newValue = !input.isEnabled
        input.isEnabled = newValue
        Log.info(newValue ? "メニューから有効にしました" : "メニューから無効にしました")
        setEnabled(newValue)
    }

    private func confirmClearHistory() {
        guard let clearHistory = actions.clearHistory else { return }
        let dialog = StatusItemDialog.clearHistoryConfirmation
        guard let index = StatusItemAlert.run(dialog), dialog.buttons[index].role == .destructive else { return }
        Log.info("メニューから履歴をクリアしました")
        clearHistory()
    }

    private func toggleLaunchAtLogin() {
        let result = LoginItemToggle.perform(using: loginItem)
        input.loginItemStatus = result.status
        switch result.outcome {
        case .completed:
            Log.info(result.status == .enabled ? "ログイン時に起動を有効にしました" : "ログイン時に起動を無効にしました")
        case .needsApproval:
            Log.info("ログイン時に起動はシステム設定での許可待ちです")
        case .failed(let error):
            Log.warning("ログイン時に起動を変更できませんでした（\(error.logSummary)）")
            StatusItemAlert.run(.loginItemFailure(error))
        case .unavailable:
            StatusItemAlert.run(.loginItemUnavailable)
        }
    }

    private static func defaultConfigFileURL(homeDirectory: String) -> URL {
        ConfigStore.defaultDirectory(homeDirectory: homeDirectory)
            .appending(path: ConfigStore.fileName, directoryHint: .notDirectory)
    }
}

extension StatusItemController: NSMenuDelegate {
    /// メニューを開く直前に、システム設定で変わり得るログイン時に起動の状態を読み直す
    public func menuNeedsUpdate(_ menu: NSMenu) {
        refreshLoginItemStatus()
    }
}
