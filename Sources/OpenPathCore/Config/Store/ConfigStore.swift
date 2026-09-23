import Foundation
import Observation

/// `~/.config/openpath/config.toml` を読み込み、ファイルの変更を監視して即時反映する（DSN-002 §6, FR-CONFIG-01）。
///
/// - `start()`: ファイルが無ければ既定値で生成し（UX-001 §7）、読み込んで監視を始める。既存のファイルは上書きしない。
/// - 読み込みに失敗したら直前の有効な設定（起動直後なら既定値）を維持し、理由を `lastError` に公開する。
/// - 設定が変わったときだけ `changes()` の購読者に新しい設定を流す。
///
/// 設定は UI（StatusItem・パレット）や AppCoordinator から同期的に読むため MainActor に隔離する。
/// 設定ファイルは数 KB で、読み込むのは保存されたときだけのため、メインスレッドで読んでも影響は小さい。
/// StatusItem がバッジを `lastError` に追従させられるよう Observable にする。
@MainActor
@Observable
public final class ConfigStore {
    public static let fileName = "config.toml"
    private static let configDirectoryName = ".config"
    /// 購読者が処理しきれない間に届いた変更は、古い設定で作業し直さないよう最新の 1 件だけを残す
    private static let bufferedChangeCount = 1

    /// 既定の設定ディレクトリ `~/.config/openpath`
    public static func defaultDirectory(homeDirectory: String = NSHomeDirectory()) -> URL {
        URL(filePath: homeDirectory, directoryHint: .isDirectory)
            .appending(path: configDirectoryName, directoryHint: .isDirectory)
            .appending(path: AppInfo.name, directoryHint: .isDirectory)
    }

    private enum Lifecycle {
        case idle
        case starting
        case running
        /// 終了処理後。再開はしない
        case stopped
    }

    public let fileURL: URL
    /// 現在有効な設定。読み込みに失敗しても直前の有効な設定のまま変わらない
    public private(set) var config: Config = .default
    /// 現在有効な設定を読み込んだときの警告（未知のキー等）。読み込みに失敗しても変わらない
    public private(set) var warnings: [ConfigWarning] = []
    /// 直近の読み込み・生成の失敗。読み込みに成功すると nil に戻る
    public private(set) var lastError: ConfigStoreError?

    private let directory: URL
    private let homeDirectory: String
    private let decoder: ConfigDecoder
    private let ghqRootProvider: any GhqRootProviding
    private let watchTiming: ConfigFileWatchTiming
    @ObservationIgnored private var lifecycle = Lifecycle.idle
    @ObservationIgnored private var monitor: ConfigFileMonitor?
    @ObservationIgnored private var subscribers: [Int: AsyncStream<Config>.Continuation] = [:]
    @ObservationIgnored private var nextSubscriberID = 0

    /// - Parameters:
    ///   - directory: 設定ファイルを置くディレクトリ。テストで実ユーザーのファイルに触れないよう、既定値を持たせず明示させる。
    ///     アプリでは `ConfigStore.defaultDirectory()` を渡す
    ///   - homeDirectory: roots の `~` の展開先。既定の設定ファイルでは ghq root を `~` で書くのにも使う
    ///   - ghqRootProvider: 既定の設定ファイルを生成するときに roots へ含める ghq root の取得元
    ///   - watchTiming: ファイル監視の開き直しとデバウンスのタイミング
    public init(
        directory: URL,
        homeDirectory: String = NSHomeDirectory(),
        ghqRootProvider: any GhqRootProviding,
        watchTiming: ConfigFileWatchTiming = .default
    ) {
        self.directory = directory
        fileURL = directory.appending(path: Self.fileName, directoryHint: .notDirectory)
        self.homeDirectory = homeDirectory
        decoder = ConfigDecoder(homeDirectory: homeDirectory)
        self.ghqRootProvider = ghqRootProvider
        self.watchTiming = watchTiming
    }

    private var filePath: String {
        fileURL.path(percentEncoded: false)
    }

    /// ファイルが無ければ既定値で生成し、監視を始めて読み込む。起動時に 1 度だけ呼ぶ（2 回目以降は何もしない）
    public func start() async {
        guard lifecycle == .idle else { return }
        lifecycle = .starting
        let generationError = await createDefaultFileIfMissing()
        // 生成を待つ間に stop された場合は監視を始めない
        guard lifecycle == .starting else { return }
        lifecycle = .running

        // 読み込みと監視の開始の間の変更を取りこぼさないよう、先に監視を始める
        let monitor = ConfigFileMonitor(fileURL: fileURL, timing: watchTiming) { [weak self] in
            self?.reload()
        }
        self.monitor = monitor
        monitor.start()

        if let generationError {
            // 読み込み直すとファイルが無いというエラーで上書きされるため、生成の失敗を公開したままにする
            logConfigError(generationError)
            lastError = generationError
            return
        }
        reload()
    }

    /// 設定ファイルを読み込み直す。監視から自動で呼ばれるほか、手動の再読み込みにも使える。
    /// 失敗したら設定と警告は直前のまま維持し、`lastError` に理由を公開する
    public func reload() {
        do throws(ConfigStoreError) {
            apply(try loadFile())
        } catch {
            // 同じ理由での失敗が続く監視イベントのたびに重複して警告を出さないよう、変わったときだけ記録する
            if lastError != error {
                logConfigError(error)
                lastError = error
            }
        }
    }

    /// `ConfigStoreError` を記録する。`description` は絶対パスを含むため、
    /// warning にはパスを含まない説明だけを出し、パスは `debugPath` に分ける（NFR-05）。
    private func logConfigError(_ error: ConfigStoreError) {
        switch error {
        case .fileNotFound(let path):
            Log.warning("設定ファイルが見つかりません")
            Log.debugPath("設定ファイルが見つかりません", path: path)
        case .readFailed(let path, let reason):
            Log.warning("設定ファイルを読み込めません")
            Log.debugPath("設定ファイルを読み込めません（\(reason)）", path: path)
        case .parseFailed(let path, let parseError):
            Log.warning("設定ファイルの書式が誤っているため反映していません（\(parseError.description)）")
            Log.debugPath("設定ファイルの書式が誤っているため反映していません", path: path)
        case .decodeFailed(let path, let decodeError):
            // ConfigDecodingError.description は invalidRootPath 等で利用者が入力した相対パスをそのまま含み得るが、
            // PathRedactor は相対パス・ファイル名までは検出できないため warning には出さず debugPath 側にまとめる
            Log.warning("設定ファイルの値が誤っているため反映していません")
            Log.debugPath("設定ファイルの値が誤っているため反映していません（\(decodeError.description)）", path: path)
        case .generationFailed(let path, let reason):
            Log.warning("設定ファイルを作成できません。既定の設定で動作します")
            Log.debugPath("設定ファイルを作成できません（\(reason)）。既定の設定で動作します", path: path)
        }
    }

    /// 監視を止め、すべての購読を終える。アプリの終了時に呼ぶ。以降 `start()` しても再開しない
    public func stop() {
        lifecycle = .stopped
        monitor?.stop()
        monitor = nil
        for continuation in subscribers.values {
            continuation.finish()
        }
        subscribers.removeAll()
    }

    /// 設定が変わるたびに新しい設定を流すストリーム。購読した時点の設定は流さないため、初期値は `config` から読むこと。
    /// 購読者が追いつかない間の変更は最新の 1 件だけを残す。`stop()` で終わる
    public func changes() -> AsyncStream<Config> {
        let (stream, continuation) = AsyncStream<Config>.makeStream(bufferingPolicy: .bufferingNewest(Self.bufferedChangeCount))
        guard lifecycle != .stopped else {
            continuation.finish()
            return stream
        }
        let subscriberID = nextSubscriberID
        nextSubscriberID += 1
        subscribers[subscriberID] = continuation
        // 設定が変わらないまま購読者が入れ替わっても溜まらないよう、購読をやめたら取り除く。
        // onTermination は任意のスレッドから呼ばれるため MainActor に戻ってから触れる
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.removeSubscriber(subscriberID)
            }
        }
        return stream
    }

    private func removeSubscriber(_ subscriberID: Int) {
        subscribers[subscriberID] = nil
    }

    // MARK: - 読み込み

    private func loadFile() throws(ConfigStoreError) -> ConfigDecodingResult {
        let source: String
        do {
            source = try String(contentsOf: fileURL, encoding: .utf8)
        } catch CocoaError.fileReadNoSuchFile {
            throw .fileNotFound(path: filePath)
        } catch {
            throw .readFailed(path: filePath, reason: error.localizedDescription)
        }

        let table: TOMLTable
        do throws(TOMLParseError) {
            table = try TOMLParser.parse(source)
        } catch {
            throw .parseFailed(path: filePath, error)
        }

        do throws(ConfigDecodingError) {
            return try decoder.decode(table)
        } catch {
            throw .decodeFailed(path: filePath, error)
        }
    }

    /// 読み込んだ結果を反映する。Observable の通知と購読者への配信は、値が変わったときだけ行う
    private func apply(_ result: ConfigDecodingResult) {
        if lastError != nil {
            lastError = nil
        }
        if warnings != result.warnings {
            // 変わらない限り再読み込みのたびに同じ警告を出さないよう、差分があるときだけ記録する
            for warning in result.warnings {
                Log.warning(warning.description)
            }
            warnings = result.warnings
        }
        guard config != result.config else { return }
        config = result.config
        for (subscriberID, continuation) in subscribers {
            // onTermination による除去は MainActor に戻るまで遅れるため、ここで終了済みと分かったものも取り除く
            if case .terminated = continuation.yield(result.config) {
                subscribers[subscriberID] = nil
            }
        }
    }

    // MARK: - 既定値の生成（UX-001 §7）

    /// ファイルが無ければ既定値で生成する。失敗したら理由を返す
    private func createDefaultFileIfMissing() async -> ConfigStoreError? {
        guard !FileManager.default.fileExists(atPath: filePath) else { return nil }

        let ghqRoot = await ghqRootProvider.root()
        guard lifecycle == .starting else { return nil }
        let contents = DefaultConfigFile.contents(ghqRoot: ghqRoot, homeDirectory: homeDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return .generationFailed(path: filePath, reason: error.localizedDescription)
        }
        do {
            // ghq を待つ間に利用者が作ったファイルや、リンク先の無いシンボリックリンクも上書きしないよう、
            // 存在すれば失敗する書き込みにする
            try Data(contents.utf8).write(to: fileURL, options: .withoutOverwriting)
        } catch CocoaError.fileWriteFileExists {
            return nil
        } catch {
            return .generationFailed(path: filePath, reason: error.localizedDescription)
        }
        return nil
    }
}
