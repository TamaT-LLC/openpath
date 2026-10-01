import AppKit

import OpenPathCore

/// パレットのキー操作（UX-001 §4）を処理し、確定・閉じる操作を `onEvent` で外へ伝える。
///
/// 入力方式: `NSEvent.addLocalMonitorForEvents` で、パレット宛ての keyDown / keyUp をウィンドウへ配送される前に受け取る。
/// - キーの振り分けは Core の `PaletteKeyBinding` に任せ、ここでは NSEvent からの変換と実行だけを行う。
/// - パレットで処理したキーは消費する（nil を返す）。検索フィールドやレスポンダチェーンには届かない。
/// - 確定（Enter / Cmd+Enter）と閉じる（Esc）は keyDown で内容を決めるが、`onEvent` で伝えるのはそのキーを
///   離したとき（keyUp）にする（`PaletteEventKeyHold`、Issue #90・#100）。伝えると、確定なら注入が始まり、
///   閉じるならパレットが隠れて、パレットがキーを手放す。押したままのリピートが背後の NSOpenPanel に届き、
///   Enter なら「開く」、Esc なら「キャンセル」が押されてしまうため。離すまではパレットがキーのままで、
///   その間の keyDown はすべてここで消費する。keyUp は観測するだけで、消費しない。
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
    private var resignKeyObserver: NSObjectProtocol?
    /// キーを離すまで預かる確定・閉じる
    private var eventKeyHold = PaletteEventKeyHold(clock: ContinuousClock())

    /// - Parameters:
    ///   - window: パレットのウィンドウ（`PaletteWindow.window`）。このウィンドウ宛てのキーだけを扱う。
    ///   - viewModel: 選択の移動・検索語の展開の適用先。ロック状態もここから読む。
    public init(window: NSWindow, viewModel: PaletteViewModel) {
        self.window = window
        self.viewModel = viewModel
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        // パネルの消滅で隠れた・パネルをクリックした等でキーでなくなったら、そのキーの keyUp はパレットに届かない。
        // 別のパネルの表示に切り替わった後に前の確定・閉じるを伝えないよう、預かっているイベントを取り消す
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cancelHeldEvent()
            }
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
        }
    }

    /// keyDown / keyUp を処理する。消費したキーは nil を返す。
    private func handle(_ event: NSEvent) -> NSEvent? {
        // パレット以外のウィンドウ宛てのキーには触れない。NSOpenPanel は別プロセスなのでそもそも届かない
        guard event.window === window else { return event }
        guard event.type == .keyDown else {
            handleKeyUp(event)
            return event
        }

        let input = PaletteKeyInput(event: event, hasMarkedText: hasMarkedText, isLocked: viewModel.isLocked)
        // 確定・閉じるのキーを離すまでは、PaletteKeyBinding に回さずすべて消費する
        switch eventKeyHold.resolve(input) {
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
            // 確定・閉じる（Esc）は、そのキーを離すまで預かる
            if let paletteEvent = viewModel.perform(action) {
                eventKeyHold.receive(paletteEvent, onKeyDownOf: event.keyCode)
            }
            return nil
        }
    }

    /// 確定・閉じるのキーを離したら、預かっていたイベントを伝える。
    private func handleKeyUp(_ event: NSEvent) {
        switch eventKeyHold.keyUp(keyCode: event.keyCode) {
        case .send(let paletteEvent):
            onEvent?(paletteEvent)
        case .expired(let paletteEvent):
            Log.debug(paletteEvent.expiredLogMessage)
        case .unrelated:
            break
        }
    }

    private func cancelHeldEvent() {
        guard let paletteEvent = eventKeyHold.cancel() else { return }
        Log.debug(paletteEvent.canceledLogMessage)
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

/// 預かっていたイベントを取り消したときの debug ログ。確定のパスは含めない。
private extension PaletteEvent {
    /// キーを上限以上押し続けたため取り消したとき
    var expiredLogMessage: String {
        let seconds = PaletteEventKeyHold.maximumHold.components.seconds
        switch self {
        case .confirm:
            return "確定のキーを \(seconds) 秒以上押し続けたため、確定を取り消しました"
        case .dismiss:
            return "Esc を \(seconds) 秒以上押し続けたため、パレットを閉じる操作を取り消しました"
        }
    }

    /// キーを離す前にパレットがキーでなくなったため取り消したとき
    var canceledLogMessage: String {
        switch self {
        case .confirm:
            return "確定のキーを離す前にパレットがキーでなくなったため、確定を取り消しました"
        case .dismiss:
            return "Esc を離す前にパレットがキーでなくなったため、パレットを閉じる操作を取り消しました"
        }
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
