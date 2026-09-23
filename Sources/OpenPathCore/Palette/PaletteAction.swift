/// キー操作によるパレット自身の操作（UX-001 §4）。`PaletteViewModel.perform(_:isDirectory:)` で適用する。
public enum PaletteAction: Equatable, Sendable {
    /// 選択を動かす（負で上、正で下）
    case moveSelection(by: Int)
    /// 選択中の候補で確定する。openImmediately は Cmd+Enter（設定に関わらず「開く」まで押す）
    case confirm(openImmediately: Bool)
    /// 選択中の候補のパスを検索語に展開する（Tab）
    case expandSelection
    /// パレットだけを閉じる（Esc）。NSOpenPanel は残す
    case dismiss
}

/// 検索フィールドの標準の編集操作。
/// openpath はメニューバー常駐でメインメニュー（編集メニュー）を持たず、Cmd+V 等がテキストフィールドに届かないため、
/// キー処理から編集のアクションを直接送る。
public enum PaletteEditCommand: Equatable, Sendable {
    case cut
    case copy
    case paste
    case selectAll
    case undo
    case redo
}

/// キー入力の扱い。
public enum PaletteKeyResolution: Equatable, Sendable {
    /// パレットの操作として実行し、キー入力は消費する
    case perform(PaletteAction)
    /// 検索フィールドの編集操作として実行し、キー入力は消費する
    case edit(PaletteEditCommand)
    /// 何もせずに消費する（ロック中や、パレットが受け持つキーの未定義の組み合わせ）
    case discard
    /// 検索フィールド（と IME）にそのまま渡す
    case passThrough
}

/// パレットから外（AppCoordinator）へ伝えるイベント。
public enum PaletteEvent: Equatable, Sendable {
    /// 候補を確定した。openImmediately は Cmd+Enter
    case confirm(path: String, openImmediately: Bool)
    /// Esc でパレットを閉じる操作をした。パレットを隠すのは AppCoordinator 側で行う
    case dismiss

    /// 対応する AppCoordinator のイベント。
    public var coordinatorEvent: CoordinatorEvent {
        switch self {
        case .confirm(let path, let openImmediately):
            .confirm(path: path, openImmediately: openImmediately)
        case .dismiss:
            .escape
        }
    }
}
