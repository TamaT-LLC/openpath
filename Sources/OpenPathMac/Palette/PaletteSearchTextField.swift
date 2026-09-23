import AppKit
import SwiftUI

/// パレットの検索フィールド（NSTextField）を SwiftUI に載せる。
///
/// SwiftUI の TextField を使わないのは、IME の変換中を扱うため。TextField は変換中の未確定文字（markedText）も
/// バインディングに流すため、確定前に候補が引き直されてちらつく。また変換中かどうかを外から判定できない。
/// NSTextField ならフィールドエディタ（NSTextView）の `hasMarkedText()` で判定でき、確定するまで
/// バインディングへの反映を保留できる（UX-001 §4）。
struct PaletteSearchTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> PaletteSearchTextFieldView {
        let field = PaletteSearchTextFieldView()
        field.placeholderString = placeholder
        field.stringValue = text
        field.onCommittedTextChange = { [coordinator = context.coordinator] committedText in
            coordinator.commit(committedText)
        }
        return field
    }

    func updateNSView(_ field: PaletteSearchTextFieldView, context: Context) {
        context.coordinator.text = $text
        field.placeholderString = placeholder
        // 変換中に書き戻すと未確定文字が消えるため、確定するまで触らない。
        // 外（Tab の展開・リセット）で検索語が変わったときだけ反映する
        guard !field.hasMarkedText, field.stringValue != text else { return }
        field.replaceText(with: text)
    }

    @MainActor
    final class Coordinator {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func commit(_ committedText: String) {
            // 同じ値の書き込みでも観測者に通知が飛ぶため、変わったときだけ書く
            guard text.wrappedValue != committedText else { return }
            text.wrappedValue = committedText
        }
    }
}

/// パレットの検索フィールドの実体。
///
/// - 確定済みの文字列が変わったときだけ `onCommittedTextChange` を呼ぶ（IME の変換中は呼ばない）。
/// - パレットがキーウィンドウになるたびにフォーカスを当て直し、カーソルを末尾に置く。Esc で隠した後の
///   ホットキーでの再表示や、新しいパネルでの表示のたびに、すぐ続けて文字を打てるようにするため。
final class PaletteSearchTextFieldView: NSTextField, NSTextFieldDelegate {
    /// 確定済みの文字列が変わったときに呼ばれる。
    var onCommittedTextChange: ((String) -> Void)?

    /// IME の変換中の未確定文字があるか。
    var hasMarkedText: Bool {
        (currentEditor() as? NSTextView)?.hasMarkedText() ?? false
    }

    /// パレットのキーはキー処理（PaletteKeyController）で消費するため、通常ここには届かない。
    /// 届いた場合もフィールドの既定動作（編集終了・フォーカス移動・補完）を起こさないよう握りつぶす。
    private static let suppressedCommands: Set<Selector> = [
        #selector(NSResponder.insertNewline(_:)),
        #selector(NSResponder.insertLineBreak(_:)),
        #selector(NSResponder.insertTab(_:)),
        #selector(NSResponder.insertBacktab(_:)),
        #selector(NSResponder.cancelOperation(_:)),
        #selector(NSResponder.complete(_:)),
    ]

    init() {
        super.init(frame: .zero)
        configureAppearance()
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - 確定済みの文字列の通知

    func controlTextDidChange(_ notification: Notification) {
        notifyCommittedTextIfNeeded()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        notifyCommittedTextIfNeeded()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        Self.suppressedCommands.contains(commandSelector)
    }

    private func notifyCommittedTextIfNeeded() {
        // IME の変換中は確定まで検索語を更新しない（候補のちらつき防止、UX-001 §4）
        guard !hasMarkedText else { return }
        onCommittedTextChange?(stringValue)
    }

    /// 外から検索語を差し替え、カーソルを末尾に置く（Tab の展開で続けて入力できるように）。
    func replaceText(with text: String) {
        guard let editor = currentEditor() as? NSTextView else {
            stringValue = text
            return
        }
        // ユーザーの編集と同じ経路で置き換え、取り消し（Cmd+Z）の履歴と整合させる
        let fullRange = NSRange(location: 0, length: (editor.string as NSString).length)
        if editor.shouldChangeText(in: fullRange, replacementString: text) {
            editor.replaceCharacters(in: fullRange, with: text)
            editor.didChangeText()
        }
        moveCaretToEnd(of: editor)
    }

    // MARK: - フォーカス

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        let notificationCenter = NotificationCenter.default
        if let window {
            notificationCenter.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
        }
        if let newWindow {
            notificationCenter.addObserver(
                self,
                selector: #selector(windowDidBecomeKey(_:)),
                name: NSWindow.didBecomeKeyNotification,
                object: newWindow
            )
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window?.isKeyWindow == true {
            focus()
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        focus()
    }

    /// 検索フィールドにフォーカスを当て、カーソルを末尾に置く。
    ///
    /// NSTextField はフォーカス時に全選択し、AppKit も表示時に最初のキービューへ自動でフォーカスする（全選択になる）。
    /// フォーカスが外れていたかどうかで再表示後の状態が変わらないよう、常に末尾へ移して続けて打てるようにする。
    /// IME の変換中は未確定文字を壊さないよう、カーソルを動かさない。
    func focus() {
        guard let window else { return }
        if currentEditor() == nil, !window.makeFirstResponder(self) {
            return
        }
        guard let editor = currentEditor() as? NSTextView, !editor.hasMarkedText() else { return }
        moveCaretToEnd(of: editor)
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        if let editor = currentEditor() as? NSTextView {
            Self.disableAutomaticEditing(of: editor)
        }
        return true
    }

    // MARK: - 見た目・入力補助

    private func configureAppearance() {
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        font = .preferredFont(forTextStyle: .title3)
        usesSingleLineMode = true
        lineBreakMode = .byClipping
        cell?.isScrollable = true
        cell?.wraps = false
        isAutomaticTextCompletionEnabled = false
        // Tab で長いパスを展開してもパレットの幅を押し広げず、フィールド内でスクロールさせる
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    /// パスやディレクトリ名の入力なので、自動修正・置換は邪魔になる。
    /// フィールドエディタはウィンドウで共有されるため、フォーカスのたびに設定する
    private static func disableAutomaticEditing(of editor: NSTextView) {
        editor.isContinuousSpellCheckingEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextCompletionEnabled = false
    }

    private func moveCaretToEnd(of editor: NSTextView) {
        let end = NSRange(location: (editor.string as NSString).length, length: 0)
        editor.setSelectedRange(end)
        editor.scrollRangeToVisible(end)
    }
}

extension PaletteSearchTextFieldView {
    /// ウィンドウ内の検索フィールドを探す。SwiftUI のホスティングビューの中に置かれるため、階層をたどる。
    static func first(in window: NSWindow) -> PaletteSearchTextFieldView? {
        window.contentView.flatMap(firstDescendant(of:))
    }

    private static func firstDescendant(of view: NSView) -> PaletteSearchTextFieldView? {
        if let field = view as? PaletteSearchTextFieldView {
            return field
        }
        for subview in view.subviews {
            if let field = firstDescendant(of: subview) {
                return field
            }
        }
        return nil
    }
}
