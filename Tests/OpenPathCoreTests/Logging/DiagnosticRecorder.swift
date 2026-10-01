import os

/// 部品が debug ログ向けに報告する診断（`diagnose`）を、報告された順に記録する。
/// 共有ロガー（`Log`）を差し替えずに、報告の中身と順序を確かめるために使う（並行に走るスイートの出力と混ざらない）。
final class DiagnosticRecorder<Diagnostic: Sendable>: Sendable {
    private let recorded = OSAllocatedUnfairLock<[Diagnostic]>(initialState: [])

    /// 報告された診断（報告された順）
    var diagnostics: [Diagnostic] {
        recorded.withLock { $0 }
    }

    func record(_ diagnostic: Diagnostic) {
        recorded.withLock { $0.append(diagnostic) }
    }
}

/// 診断ログの文言の約束。
enum DiagnosticLogContract {
    /// ログを読むスクリプト（`scripts/smoke-open-panel.sh`・`scripts/measure-detection-latency.sh`）が行の部分一致で探す目印。
    /// 診断の行がこれらを含むと、検知や表示の行と取り違えられるため含めない。
    static let scriptMarkers = ["panel detected", "palette shown", "panel gone", "を起動します"]

    /// パス（"/" を含む）・スクリプトの目印を含まないか。
    static func isSafe(_ message: String) -> Bool {
        !message.contains("/") && !scriptMarkers.contains { message.contains($0) }
    }
}
