/// 開くパネルの選択モードの推定結果と、推定し直す予定（DSN-001 §2.3）。`OpenPanelLocator` がパネルの要素ごとに持つ。
///
/// 推定は、開くパネルと判定したときに行う。パネルの選択モード（`canChooseFiles` / `canChooseDirectories`）は開いている間
/// 変わらないため、行を読めたときの結果は（推定できなかった場合も含めて）確定とし、フォルダを移動しても推定し直さない。
/// PanelShown 中の走査で行を読み直し、AX の呼び出しを増やさないためでもある（DSN-001 §5）。
///
/// 種類の分かる行を 1 行も読めなかった場合（一覧の読み込み前、読み取りの失敗）だけは、判定の再確認と同じ間隔
/// （`OpenPanelCacheConfiguration` の、倍々に空ける待ち時間と回数）で推定し直す。読めない間の読み取りは数回で済む。
///
/// 推定し直すのは、その時刻より後の走査のとき。推定し直す予定の間は `PanelContext.isSelectionModeProvisional` を立て、
/// PanelWatchPolicy がパレットの表示中（PanelShown）も補助ポーリングを続けて走査の機会を作る。
/// 推定し直した結果フォルダのみかどうかが変わったら、PanelWatchPolicy が `panelContextChanged` で表示中のパレットへ知らせる。
struct SelectionModeState<Node> {
    /// 推定結果と、推定に使った行の内訳
    private(set) var estimate: PanelSelectionEstimate
    /// 推定し直す予定。nil なら推定は確定している
    private var retry: Retry?

    /// 後で推定し直す予定があるか
    var isProvisional: Bool {
        retry != nil
    }

    /// fileList の先頭の行（先頭がディレクトリばかりなら末尾の行も。`FileListRowSampler.sample`）から推定する。
    init<Reader: PanelTreeReader>(
        fileList: FileListElement<Node>?,
        reader: Reader,
        now: ContinuousClock.Instant,
        configuration: OpenPanelCacheConfiguration
    ) where Reader.Node == Node {
        estimate = .notSampled
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
        self.estimate = estimate.result
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
            let sample = try FileListRowSampler.sample(in: fileList.node, role: fileList.role, reader: reader)
            let result = PanelSelectionModeEstimator.estimate(sample)
            return Estimate(result: result, hasReadableRows: result.sampledDirectoryCount + result.sampledFileCount > 0)
        } catch {
            return Estimate(result: .notSampled, hasReadableRows: false)
        }
    }
}

extension SelectionModeState {
    private struct Estimate {
        let result: PanelSelectionEstimate
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
