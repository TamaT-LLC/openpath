/// メニューバーのアイコン・ツールチップ・メニューの表示内容（UX-001 §5, §6）。
///
/// `StatusMenuInput` から決まる純粋な値で、Mac 層は NSStatusItem / NSMenu へ反映するだけにする。
/// メニューは次の順に並べる。
///
/// 1. 通知（権限なし → 設定エラー → クリップボードの復元失敗の順）と区切り線。通知が無ければ省く
/// 2. 有効
/// 3. 候補を再構築 / 設定ファイルを開く… / 履歴をクリア…
/// 4. ログイン時に起動 / アクセシビリティ設定を開く…（未付与時のみ）
/// 5. 終了
public struct StatusMenuState: Sendable, Equatable {
    public let icon: StatusIconState
    /// アイコンのツールチップ。1 行目はアプリ名、以降は通知を 1 行ずつ
    public let toolTip: String
    /// バッジを付けた原因。権限を先に並べる
    public let notices: [StatusNotice]
    /// メニューの並び
    public let entries: [StatusMenuEntry]

    public init(_ input: StatusMenuInput) {
        let notices = Self.notices(for: input)
        self.notices = notices
        icon = StatusIconState(hasBadge: !notices.isEmpty, isDimmed: !input.isEnabled)
        toolTip = Self.toolTip(isEnabled: input.isEnabled, notices: notices)
        entries = Self.entries(for: input, notices: notices)
    }

    /// メニューに並ぶ操作の項目（通知と区切り線を除く）
    public var commandItems: [StatusMenuItem] {
        entries.compactMap { entry in
            guard case .command(let item) = entry else { return nil }
            return item
        }
    }

    /// 指定した操作の項目。メニューに出さない場合は nil
    public func item(for command: StatusMenuCommand) -> StatusMenuItem? {
        commandItems.first { $0.command == command }
    }

    // MARK: - 算出

    private static func notices(for input: StatusMenuInput) -> [StatusNotice] {
        var notices: [StatusNotice] = []
        // 権限が無いとパネルの検知そのものが動かないため、設定のエラーより先に出す
        if !input.accessibilityPermission.isGranted {
            notices.append(.accessibilityPermissionMissing)
        }
        if let configError = input.configError {
            notices.append(.configError(configError))
        }
        // 動作には影響しない事後の知らせのため最後に出す
        if input.hasClipboardRestoreFailure {
            notices.append(.clipboardRestoreFailed)
        }
        return notices
    }

    private static func toolTip(isEnabled: Bool, notices: [StatusNotice]) -> String {
        let header = isEnabled ? AppInfo.name : "\(AppInfo.name)（\(StatusMenuText.disabledSuffix)）"
        let noticeLines = notices.map { "\($0.title)\(StatusMenuText.noticeSeparator)\($0.detail)" }
        return ([header] + noticeLines).joined(separator: StatusMenuText.lineSeparator)
    }

    private static func entries(for input: StatusMenuInput, notices: [StatusNotice]) -> [StatusMenuEntry] {
        var entries: [StatusMenuEntry] = notices.map { .notice($0) }
        if !notices.isEmpty {
            entries.append(.separator)
        }

        entries.append(.command(StatusMenuItem(command: .toggleEnabled, checkState: input.isEnabled ? .on : .off)))
        entries.append(.separator)

        entries.append(.command(StatusMenuItem(command: .rebuildCandidates)))
        entries.append(.command(StatusMenuItem(command: .openConfigFile)))
        entries.append(.command(StatusMenuItem(command: .clearHistory)))
        entries.append(.separator)

        entries.append(.command(loginItem(for: input.loginItemStatus)))
        if !input.accessibilityPermission.isGranted {
            entries.append(.command(StatusMenuItem(command: .openAccessibilitySettings)))
        }
        entries.append(.separator)

        entries.append(.command(StatusMenuItem(command: .quit)))
        return entries
    }

    private static func loginItem(for status: LoginItemStatus) -> StatusMenuItem {
        StatusMenuItem(
            command: .toggleLaunchAtLogin,
            checkState: status.checkState,
            isEnabled: status.toggleCommand != nil,
            toolTip: status.note
        )
    }
}
