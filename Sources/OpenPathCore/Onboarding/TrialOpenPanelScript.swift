import Foundation

/// 「試してみる」で「開く」ダイアログを出す方法（UX-001 §7）。
///
/// `osascript` の `choose folder` を別プロセスで動かし、そのプロセスに NSOpenPanel（フォルダ選択）を出させる。
/// - openpath 自身のプロセスで NSOpenPanel を出すと、PanelWatcher は自プロセスを観測しないため検知できない
/// - Finder には「開く」ダイアログが無く（⌘O は選択中の項目を開く）、他のアプリを前面にしてキーを送る方法は、
///   前面が入れ替わったときに意図しないアプリへ入力してしまうおそれがある
/// - `tell` で他のアプリへ命令を送らないため、オートメーション（Apple Events）の許可も求めない（NFR-02）
/// 選ばれたフォルダは使わない（試すだけ）。
public enum TrialOpenPanelScript {
    public static let executablePath = "/usr/bin/osascript"
    /// ダイアログに添える案内
    static let prompt = OnboardingText.trialPanelPrompt
    private static let scriptOption = "-e"

    /// `osascript` に渡す引数
    public static var arguments: [String] {
        [scriptOption, "choose folder with prompt " + AppleScriptLiteral.string(prompt)]
    }
}

/// AppleScript のリテラルの組み立て。
enum AppleScriptLiteral {
    private static let quote = "\""
    private static let backslash = "\\"

    /// 文字列リテラル。バックスラッシュと引用符をエスケープし、引用符で囲む
    static func string(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: backslash, with: backslash + backslash)
            .replacingOccurrences(of: quote, with: backslash + quote)
        return quote + escaped + quote
    }
}
