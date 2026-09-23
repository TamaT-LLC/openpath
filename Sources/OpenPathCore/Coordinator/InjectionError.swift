/// パス注入の失敗理由（DSN-001 §3.3 のエラー分類）。
public enum InjectionError: Error, Equatable, Sendable {
    case timeout(step: InjectionStep)
    /// AX API の失敗。code は AXError の rawValue（Core に AX の型を持ち込まないため数値で持つ）。
    case axError(code: Int32)
    /// 注入先のパネルが消えていた。
    case panelGone
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
        }
    }
}
