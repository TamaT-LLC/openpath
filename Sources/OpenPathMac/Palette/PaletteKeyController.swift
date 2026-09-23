import AppKit

import OpenPathCore

/// パレットのキー操作（UX-001 §4）を処理し、確定・閉じる操作を `onEvent` で外へ伝える。
///
/// 入力方式: `NSEvent.addLocalMonitorForEvents` で、パレット宛ての keyDown をウィンドウへ配送される前に受け取る。
/// - キーの振り分けは Core の `PaletteKeyBinding` に任せ、ここでは NSEvent からの変換と実行だけを行う。
/// - パレットで処理したキーは消費する（nil を返す）。検索フィールドやレスポンダチェーンには届かない。
/// - IME の変換中はパレットの操作にせず、そのまま IME（検索フィールドの入力コンテキスト）へ渡す。
///   変換中かどうかはキーを受け取った時点のフィールドエディタの `hasMarkedText()` で判定する。
/// - キーウィンドウかどうかはイベントの送り先で判定する。パレットがキーの間は `NSApp.isActive` が
///   true になるため、アプリの状態では判定しない。
///
/// 生成するとすぐに監視を始め、解放で止める。配線側で保持し続けること。
@MainActor
public final class PaletteKeyController {
    /// 確定・閉じる操作が行われたときに呼ばれる。`PaletteEvent.coordinatorEvent` で AppCoordinator へ渡す。
    public var onEvent: ((PaletteEvent) -> Void)?

    private let window: NSWindow
    private let viewModel: PaletteViewModel
    private var monitor: Any?

    /// - Parameters:
    ///   - window: パレットのウィンドウ（`PaletteWindow.window`）。このウィンドウ宛てのキーだけを扱う。
    ///   - viewModel: 選択の移動・検索語の展開の適用先。ロック状態もここから読む。
    public init(window: NSWindow, viewModel: PaletteViewModel) {
        self.window = window
        self.viewModel = viewModel
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// keyDown を処理する。消費したキーは nil を返す。
    private func handle(_ event: NSEvent) -> NSEvent? {
        // パレット以外のウィンドウ宛てのキーには触れない。NSOpenPanel は別プロセスなのでそもそも届かない
        guard event.window === window else { return event }

        let input = PaletteKeyInput(event: event, hasMarkedText: hasMarkedText, isLocked: viewModel.isLocked)
        switch PaletteKeyBinding.resolve(input) {
        case .passThrough:
            focusSearchFieldIfNeeded()
            return event
        case .discard:
            return nil
        case .edit(let command):
            focusSearchFieldIfNeeded()
            NSApp.sendAction(command.selector, to: nil, from: nil)
            return nil
        case .perform(let action):
            if let paletteEvent = viewModel.perform(action) {
                onEvent?(paletteEvent)
            }
            return nil
        }
    }

    /// 検索フィールドの編集中はフィールドエディタ（NSTextView）がファーストレスポンダになる。
    private var hasMarkedText: Bool {
        (window.firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    /// 候補行のクリック等で検索フィールドからフォーカスが外れていても、打った文字が検索フィールドに入るようにする。
    private func focusSearchFieldIfNeeded() {
        guard !(window.firstResponder is NSTextView) else { return }
        PaletteSearchTextFieldView.first(in: window)?.focus()
    }
}

extension PaletteKeyInput {
    init(event: NSEvent, hasMarkedText: Bool, isLocked: Bool) {
        self.init(
            keyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            modifiers: PaletteKeyModifiers(event.modifierFlags),
            isRepeat: event.isARepeat,
            hasMarkedText: hasMarkedText,
            isLocked: isLocked
        )
    }
}

extension PaletteKeyModifiers {
    /// Caps Lock・テンキー・ファンクションキーのフラグ（矢印キーで立つ）は判定に使わないため落とす。
    init(_ flags: NSEvent.ModifierFlags) {
        let mapping: [(NSEvent.ModifierFlags, PaletteKeyModifiers)] = [
            (.control, .control),
            (.option, .option),
            (.shift, .shift),
            (.command, .command),
        ]
        self = mapping.reduce(into: []) { modifiers, pair in
            if flags.contains(pair.0) {
                modifiers.insert(pair.1)
            }
        }
    }
}

extension PaletteEditCommand {
    /// レスポンダチェーン（検索フィールドのフィールドエディタ）へ送るアクション。
    var selector: Selector {
        switch self {
        case .cut: #selector(NSText.cut(_:))
        case .copy: #selector(NSText.copy(_:))
        case .paste: #selector(NSText.paste(_:))
        case .selectAll: #selector(NSText.selectAll(_:))
        // undo: / redo: はウィンドウがアンドゥマネージャへ中継する（編集メニューと同じアクション）
        case .undo: Selector(("undo:"))
        case .redo: Selector(("redo:"))
        }
    }
}
