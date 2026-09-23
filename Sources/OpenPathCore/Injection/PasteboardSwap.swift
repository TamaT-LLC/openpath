/// 注入の間だけペーストボードをパスに差し替え、元の内容に戻す（FR-INJECT-04、DSN-001 §3.1 ステップ 1, 2, 9）。
@MainActor
public final class PasteboardSwap {
    public enum SwapError: Error, Equatable {
        /// パスを書き込めなかった。元の内容は戻してある。
        case writeFailed
    }

    public enum RestoreOutcome: Equatable, Sendable {
        /// 元の内容を書き戻した。
        case restored
        /// 差し替えた後に他のアプリやユーザーが書き換えていたため、新しい内容を優先して戻さなかった。
        case skippedBecauseReplacedByOthers
        /// 書き戻しに失敗した。
        case failed
        /// 既に復元（または復元の見送り）を済ませていた。
        case alreadyRestored
    }

    /// 差し替える前の内容。
    public let original: PasteboardSnapshot
    private let pasteboard: any PasteboardAccessing
    /// 差し替えた直後の changeCount。復元時にこれと異なれば、その後に誰かが書き込んでいる。
    private let changeCountAfterSwap: Int
    private var isFinished = false

    /// 現在の内容を退避してから text を書き込む。
    /// - Throws: 書き込めなかった場合 `SwapError.writeFailed`。
    public init(replacingContentsOf pasteboard: any PasteboardAccessing, with text: String) throws {
        let original = PasteboardSnapshot.capture(from: pasteboard)
        guard pasteboard.replaceContents(with: .transientText(text)) else {
            // 消去だけ済んで書き込めなかった場合に備え、元の内容へ戻してから失敗を返す
            _ = pasteboard.replaceContents(with: original)
            throw SwapError.writeFailed
        }
        self.original = original
        self.pasteboard = pasteboard
        changeCountAfterSwap = pasteboard.changeCount
    }

    /// 元の内容へ戻す。何度呼んでも書き戻すのは 1 回だけ。
    @discardableResult
    public func restore() -> RestoreOutcome {
        guard !isFinished else { return .alreadyRestored }
        isFinished = true
        // 注入中にユーザーがコピーした内容を、古い内容で上書きして失わせないため
        guard pasteboard.changeCount == changeCountAfterSwap else { return .skippedBecauseReplacedByOthers }
        return pasteboard.replaceContents(with: original) ? .restored : .failed
    }
}
