/// PanelWatcher が info で出すパネルの検知のログの文言（DSN-001 §2.2、§2.3）。パスは含まない。
///
/// `panel detected (id: …, directoriesOnly: …` までの書式は、スモークスクリプト（`scripts/smoke-open-panel.sh`）と
/// 計測スクリプト（#30）が読むため変えない。後ろに選択モードの推定結果と、推定に使った行の内訳を続け、
/// `directoriesOnly: false` が「ファイルも選べる」なのか「推定できない」なのか、推定できない理由
/// （行を読めない・ディレクトリしかない・選べるかを読めない）はどれかを、リリースビルドのログでも見分けられるようにする（Issue #73）。
public enum PanelWatchLogMessage {
    /// パネルの消滅。
    public static let panelGone = "panel gone"

    /// パネルの出現（`CoordinatorEvent.panelAppeared`）。
    /// 例: `panel detected (id: open-panel-1, directoriesOnly: false, selectionMode: undetermined, sampledRows: 15, sampledDirectories: 15, sampledFiles: 0)`
    /// - Parameter estimate: 選択モードの推定結果。分からなければ nil（`directoriesOnly` までを出す）。
    public static func panelDetected(_ panel: PanelContext, estimate: PanelSelectionEstimate?) -> String {
        message("panel detected", panel: panel, estimate: estimate)
    }

    /// 通知済みのパネルの情報の変化（`CoordinatorEvent.panelContextChanged`）。書式は `panelDetected` と同じ。
    public static func panelUpdated(_ panel: PanelContext, estimate: PanelSelectionEstimate?) -> String {
        message("panel updated", panel: panel, estimate: estimate)
    }

    private static func message(_ event: String, panel: PanelContext, estimate: PanelSelectionEstimate?) -> String {
        var fields = ["id: \(panel.id.rawValue)", "directoriesOnly: \(panel.isDirectoriesOnly)"]
        if let estimate {
            fields += [
                "selectionMode: \(estimate.mode)",
                "sampledRows: \(estimate.sampledRowCount)",
                "sampledDirectories: \(estimate.sampledDirectoryCount)",
                "sampledFiles: \(estimate.sampledFileCount)",
            ]
        }
        return "\(event) (\(fields.joined(separator: ", ")))"
    }
}
