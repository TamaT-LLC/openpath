import Foundation

/// 設定 `roots` の 1 ルート配下を `depth` まで走査し、候補を集める（FR-SOURCE-02 / 05, DSN-002 §3）。
///
/// 走査の方針:
/// - ルート自身も候補に含める（depth 0 ならルートのみ）。ルートは設定で明示されたものなので隠し・ignore の判定は
///   ルート自身には適用せず、シンボリックリンクならリンク先を走査する
/// - 隠しファイル（名前が `.` で始まる項目と、隠し属性 UF_HIDDEN の項目。ホームの `Library` も後者）と、
///   名前が `ignoredNames` に一致する項目は除外し、ディレクトリなら配下にも潜らない
/// - 配下のシンボリックリンクはリンク先の種別で候補に含めるが、中には潜らない（循環の防止）。リンク切れは含めない
/// - パッケージ（`.app` 等）は中に潜らず、ファイルとして扱う
/// - 存在しない・読めないルートはエラーにせず警告を返す。読めないサブディレクトリは飛ばして続ける
/// - 候補が `itemLimit` を超えた時点で打ち切り、警告を返す
///
/// ファイルシステムを同期的に読むため、メインスレッドではなくバックグラウンドのタスクから呼ぶこと（DSN-002 §3）。
public struct RootDirectoryScanner: Sendable {
    /// 列挙された 1 件の種別
    private enum EntryKind {
        /// 中に潜る対象のディレクトリ（パッケージを除く）
        case traversableDirectory
        /// シンボリックリンク。リンク自体は isDirectory が false になるため、種別はリンク先で決める
        case symbolicLink
        /// 通常ファイルとパッケージ
        case file
    }

    // isPackageKey は LaunchServices を引くため先読みせず、拡張子のあるディレクトリにだけ問い合わせる
    private static let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
    private static let resourceKeySet = Set(resourceKeys)
    private static let enumerationOptions: FileManager.DirectoryEnumerationOptions = [
        .skipsHiddenFiles,
        .skipsPackageDescendants,
    ]

    public let options: RootScanOptions
    private let isCancelled: @Sendable () -> Bool

    /// - Parameters:
    ///   - options: 走査の条件。
    ///   - isCancelled: 走査を中断すべきか。既定は呼び出し元タスクのキャンセル状態。
    ///     テストでは列挙の途中でキャンセルされた状況を再現するために差し替える。
    public init(options: RootScanOptions, isCancelled: @escaping @Sendable () -> Bool = { Task.isCancelled }) {
        self.options = options
        self.isCancelled = isCancelled
    }

    /// ルート配下を走査する。
    /// - Parameter root: 走査するディレクトリの絶対パス。候補のパスはこの表記を起点に組み立てる。
    /// - Throws: 走査中に `isCancelled` が true を返したら `CancellationError`。
    public func scan(root: String) throws -> CandidateSourceSnapshot {
        try checkCancellation()
        if let reason = Self.unavailableReason(ofRoot: root) {
            return CandidateSourceSnapshot(items: [], warnings: [.rootUnavailable(root: root, reason: reason)])
        }
        var collector = RootItemCollector(root: root, limit: options.itemLimit)
        let isRootCollected = collector.append(SourceItem(path: root, isDirectory: true))
        if isRootCollected && options.depth > 0 {
            try collectDescendants(of: root, into: &collector)
        }
        return collector.snapshot()
    }

    private func collectDescendants(of root: String, into collector: inout RootItemCollector) throws {
        // シンボリックリンクのルートはそのままでは列挙できないため、リンク先を列挙する
        let rootURL = URL(filePath: root, directoryHint: .isDirectory).resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Self.resourceKeys,
            options: Self.enumerationOptions,
            // 読めないサブディレクトリがあっても残りの走査は続ける
            errorHandler: { _, _ in true }
        ) else {
            return
        }

        var paths = DescendantPathBuilder(root: root)
        while let url = enumerator.nextObject() as? URL {
            try checkCancellation()
            let level = enumerator.level
            let name = url.lastPathComponent
            let path = paths.path(forName: name, level: level)
            // 列挙後に消えた項目は種別を決められないため飛ばす
            guard let entryKind = Self.entryKind(of: url) else {
                continue
            }
            let isIgnored = options.ignoredNames.contains(name)
            if entryKind == .traversableDirectory, isIgnored || level >= options.depth {
                enumerator.skipDescendants()
            }
            guard !isIgnored, level <= options.depth, let item = item(atPath: path, entryKind: entryKind) else {
                continue
            }
            guard collector.append(item) else {
                // 警告は戻り値の CandidateSourceWarning にも残る。ルートはパスなので debugPath に分ける
                Log.warning("候補がルートあたりの上限（\(options.itemLimit) 件）に達したため、走査を打ち切りました")
                Log.debugPath("候補が上限に達したため走査を打ち切りました", path: root)
                return
            }
        }
    }

    /// 候補にするなら SourceItem を返す。ファイルは `includeFiles` のときだけ含める。
    private func item(atPath path: String, entryKind: EntryKind) -> SourceItem? {
        let kind: FileSystemItemKind? = switch entryKind {
        case .traversableDirectory:
            .directory
        case .file:
            .file
        case .symbolicLink:
            FileSystemItemKind.ofItem(atPath: path)
        }
        switch kind {
        case .directory:
            return SourceItem(path: path, isDirectory: true)
        case .file:
            return options.includeFiles ? SourceItem(path: path, isDirectory: false) : nil
        case nil:
            return nil
        }
    }

    private func checkCancellation() throws {
        if isCancelled() {
            throw CancellationError()
        }
    }

    private static func entryKind(of url: URL) -> EntryKind? {
        guard let values = try? url.resourceValues(forKeys: resourceKeySet) else {
            return nil
        }
        if values.isSymbolicLink == true {
            return .symbolicLink
        }
        if values.isDirectory == true, !FileSystemItemKind.isPackage(directoryAt: url) {
            return .traversableDirectory
        }
        return .file
    }

    private static func unavailableReason(ofRoot root: String) -> RootUnavailableReason? {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        // fileExists はシンボリックリンクを辿るため、リンク切れのルートは存在しない扱いになる
        guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory) else {
            return .notFound
        }
        guard isDirectory.boolValue else {
            return .notDirectory
        }
        // 中身の一覧には読み取りと検索（実行）の両方の権限が要る
        guard fileManager.isReadableFile(atPath: root), fileManager.isExecutableFile(atPath: root) else {
            return .unreadable
        }
        return nil
    }
}
