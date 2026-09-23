/// 初回起動の案内の段階（UX-001 §7）。
///
/// 未表示 → 権限の説明 → 権限待ち → 完了、または途中で閉じてスキップ。
/// 起動時に権限が既にあれば、説明と権限待ちを飛ばして完了から始める。
public enum OnboardingStep: Sendable, Equatable {
    /// まだ案内を出していない（以前に案内を終えていれば、この段階のまま出さない）
    case notShown
    /// アクセシビリティ権限を何に使うかを説明している
    case explainingPermission
    /// システム設定を開き、権限の付与を待っている
    case awaitingPermission
    /// 権限があり、設定ファイルを用意した。「試してみる」を出す（案内を閉じた後もこの段階のまま）
    case completed
    /// 権限を付与しないまま案内を閉じた
    case skipped
}
