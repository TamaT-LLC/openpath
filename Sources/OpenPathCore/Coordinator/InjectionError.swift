/// パス注入の失敗理由（DSN-001 §3.3 のエラー分類）。
public enum InjectionError: Error, Equatable, Sendable {
    case timeout(step: InjectionStep)
    /// AX API の失敗。code は AXError の rawValue（Core に AX の型を持ち込まないため数値で持つ）。
    case axError(code: Int32)
    /// 注入先のパネルが消えていた。
    case panelGone
    /// 注入に使ったペーストボードを元の内容へ戻せなかった（FR-INJECT-04）。
    /// パネルの移動自体は済んでいる場合があるが、ユーザーのクリップボードが失われたことを知らせるため失敗として扱う。
    case pasteboardRestoreFailed
    /// 注入先のアプリが最前面でなくなったため、キー操作・AX 操作を送らずにやめた（別のアプリへの誤送出の防止）。
    /// パネルは残っている場合があるため panelGone とは分ける（自動確定中の panelGone は「開く」で閉じた成功とみなされるため）。
    case targetNotFrontmost
    /// 自動確定（auto_confirm / Cmd+Enter）の注入で、「開く」を押す前にパネルが消えた。
    /// 自動確定中の panelGone は「開く」で閉じた成功とみなされるため、押す前の消滅はこちらで伝えて履歴に残さない。
    case panelGoneBeforeConfirm
}

/// タイムアウトした注入ステップ（DSN-001 §3.1）。
public enum InjectionStep: String, Sendable {
    /// Cmd+Shift+G の移動先シートの出現待ち
    case waitSheet
    /// ペーストの反映待ち
    case waitPaste
    /// AppCoordinator の全体タイムアウト。どのステップで止まったかは分からない。
    case overall
}

extension InjectionError {
    /// パレットのフッターに出す文言。パネル消滅時はパレットごと閉じるため nil。
    public var userMessage: String? {
        switch self {
        case .timeout(step: .waitSheet):
            PaletteMessage.injectionFailed(reason: "⌘⇧G が開きません")
        case .timeout(step: .waitPaste):
            PaletteMessage.injectionFailed(reason: "パスの貼り付けに失敗")
        case .timeout(step: .overall):
            PaletteMessage.injectionTimedOut
        case .axError(let code):
            PaletteMessage.injectionFailed(reason: "アクセシビリティ操作に失敗 (\(code))")
        case .panelGone:
            nil
        case .pasteboardRestoreFailed:
            PaletteMessage.pasteboardRestoreFailed
        case .targetNotFrontmost:
            PaletteMessage.injectionFailed(reason: "別のアプリに切り替わりました")
        case .panelGoneBeforeConfirm:
            PaletteMessage.injectionFailed(reason: "パネルが閉じられました")
        }
    }
}
