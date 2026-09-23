/// 開くパネルの選択モードの推定結果と、推定し直す予定（DSN-001 §2.3）。`OpenPanelLocator` がパネルの要素ごとに持つ。
///
/// 推定は、開くパネルと判定したときに行う。パネルの選択モード（`canChooseFiles` / `canChooseDirectories`）は開いている間
/// 変わらないため、行を読めたときの結果は（推定できなかった場合も含めて）確定とし、フォルダを移動しても推定し直さない。
/// PanelShown 中の走査で行を読み直し、AX の呼び出しを増やさないためでもある（DSN-001 §5）。
///
/// 種類の分かる行を 1 行も読めなかった場合（一覧の読み込み前、読み取りの失敗）だけは、判定の再確認と同じ間隔
/// （`OpenPanelCacheConfiguration` の、倍々に空ける待ち時間と回数）で推定し直す。読めない間の読み取りは数回で済む。
///
/// 推定し直すのは、その時刻より後の走査（Idle 中のポーリング、AX 通知）のときで、専用の走査は予約しない。
/// 推定し直した結果は PanelWatchPolicy の追跡中のパネルに反映されるが、AppCoordinator が使うのは通知の時点の
/// `PanelContext` のため、表示中のパレットには届かない（Idle に戻った後の再通知から使われる）。
struct SelectionModeState<Node> {
    private(set) var mode: PanelSelectionMode
    /// 推定し直す予定。nil なら推定は確定している
    private var retry: Retry?

    /// fileList の先頭の行から推定する。
    init<Reader: PanelTreeReader>(
        fileList: FileListElement<Node>?,
        reader: Reader,
        now: ContinuousClock.Instant,
        configuration: OpenPanelCacheConfiguration
    ) where Reader.Node == Node {
        mode = .undetermined
        guard let fileList else { return }
        apply(
            Self.estimate(fileList, reader: reader),
            fileList: fileList,
            completedRetries: 0,
            now: now,
            configuration: configuration
        )
    }

    /// 推定し直す時刻になっていれば、推定し直す。
    mutating func refreshIfDue<Reader: PanelTreeReader>(
        reader: Reader,
        now: ContinuousClock.Instant,
        configuration: OpenPanelCacheConfiguration
    ) where Reader.Node == Node {
        guard let retry, now >= retry.notBefore else { return }
        apply(
            Self.estimate(retry.fileList, reader: reader),
            fileList: retry.fileList,
            completedRetries: retry.completedRetries + 1,
            now: now,
            configuration: configuration
        )
    }

    private mutating func apply(
        _ estimate: Estimate,
        fileList: FileListElement<Node>,
        completedRetries: Int,
        now: ContinuousClock.Instant,
        configuration: OpenPanelCacheConfiguration
    ) {
        mode = estimate.mode
        guard !estimate.hasReadableRows, completedRetries < configuration.maxRechecks else {
            retry = nil
            return
        }
        let delay = configuration.recheckDelay(afterRechecks: completedRetries)
        retry = Retry(fileList: fileList, completedRetries: completedRetries, notBefore: now.advanced(by: delay))
    }

    /// 推定の失敗でパネルの検知を妨げないよう、読み取りに失敗したら（行が消えた、応答がないなど）推定できなかったものとし、
    /// 設定 include_files に従わせる。
    private static func estimate<Reader: PanelTreeReader>(
        _ fileList: FileListElement<Node>,
        reader: Reader
    ) -> Estimate where Reader.Node == Node {
        do {
            let rows = try FileListRowSampler.sampleRows(in: fileList.node, role: fileList.role, reader: reader)
            return Estimate(
                mode: PanelSelectionModeEstimator.estimate(rows),
                hasReadableRows: rows.contains { $0.isDirectory != nil }
            )
        } catch {
            return Estimate(mode: .undetermined, hasReadableRows: false)
        }
    }
}

extension SelectionModeState {
    private struct Estimate {
        let mode: PanelSelectionMode
        /// 種類の分かる行を読めたか。読めなかったら推定し直す
        let hasReadableRows: Bool
    }

    private struct Retry {
        let fileList: FileListElement<Node>
        /// これまでに推定し直した回数
        let completedRetries: Int
        let notBefore: ContinuousClock.Instant
    }
}
