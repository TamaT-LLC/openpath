import Foundation

/// 設定ファイルの変更を監視し、読み込み直すべきときに `onChange` を呼ぶ（DSN-002 §6）。
///
/// - ファイル自体を監視し、同じ inode への書き込み（上書き保存）を検知する。
/// - rename / delete（エディタのアトミック保存など）を検知したら `reopenDelay` 後にパスを開き直して監視を張り直し、
///   置き換わった内容を読み込み直す。まだファイルが無ければ `maxReopenAttempts` 回まで繰り返し、
///   それでも無ければファイルが無いことを知らせるため読み込み直す（読み込み側が失敗を公開する）。
/// - 開き直しを諦めた後に作り直されたファイルにも追従できるよう、親ディレクトリも監視する。
/// - 連続したイベントは `debounceInterval` でまとめ、1 回の保存で何度も読み込み直さない。
///
/// DispatchSource のイベントはメインキューで受け取り、状態はすべて MainActor 上で扱う。
@MainActor
final class ConfigFileMonitor {
    private static let fileEventMask: DispatchSource.FileSystemEvent = [.write, .rename, .delete]
    /// 監視中の inode が設定ファイルのパスから外れたことを示すイベント
    private static let detachingEvents: DispatchSource.FileSystemEvent = [.rename, .delete]
    /// ディレクトリのエントリの追加・削除・rename は、ディレクトリへの write として届く
    private static let directoryEventMask: DispatchSource.FileSystemEvent = .write
    private static let firstReopenAttempt = 1

    private let fileURL: URL
    private let timing: ConfigFileWatchTiming
    private let onChange: @MainActor () -> Void

    private var isRunning = false
    private var fileSource: FileSystemEventSource?
    private var directorySource: FileSystemEventSource?
    private var pendingReopen: Task<Void, Never>?
    private var pendingChange: Task<Void, Never>?

    init(fileURL: URL, timing: ConfigFileWatchTiming, onChange: @escaping @MainActor () -> Void) {
        self.fileURL = fileURL
        self.timing = timing
        self.onChange = onChange
    }

    /// 監視を始める。ファイルがまだ無ければ、作られたときにディレクトリの監視で拾う
    func start() {
        guard !isRunning else { return }
        isRunning = true
        directorySource = FileSystemEventSource(
            url: fileURL.deletingLastPathComponent(),
            eventMask: Self.directoryEventMask
        ) { [weak self] _ in
            self?.handleDirectoryEvent()
        }
        openFileSource()
    }

    /// 監視を止め、保留中の開き直しと読み込み直しも取り消す
    func stop() {
        isRunning = false
        pendingReopen?.cancel()
        pendingReopen = nil
        pendingChange?.cancel()
        pendingChange = nil
        fileSource?.cancel()
        fileSource = nil
        directorySource?.cancel()
        directorySource = nil
    }

    /// パスを開いて監視を張る。開けたら true
    @discardableResult
    private func openFileSource() -> Bool {
        fileSource = FileSystemEventSource(url: fileURL, eventMask: Self.fileEventMask) { [weak self] event in
            self?.handleFileEvent(event)
        }
        return fileSource != nil
    }

    private func handleFileEvent(_ event: DispatchSource.FileSystemEvent) {
        guard isRunning else { return }
        if !event.isDisjoint(with: Self.detachingEvents) {
            // 監視中の inode はもう設定ファイルのパスに無い。新しいファイルが置かれるのを待って開き直す
            fileSource?.cancel()
            fileSource = nil
            scheduleReopen(attempt: Self.firstReopenAttempt)
        } else if event.contains(.write) {
            scheduleChange()
        }
    }

    /// ファイルを監視できていない間にファイルが作られた（開き直しを諦めた後の再作成など）ときだけ開き直す。
    /// それ以外のエントリの変化（エディタの一時ファイル等）はファイル側の監視で足りるため無視する
    private func handleDirectoryEvent() {
        guard isRunning, fileSource == nil, pendingReopen == nil else { return }
        scheduleReopen(attempt: Self.firstReopenAttempt)
    }

    private func scheduleReopen(attempt: Int) {
        pendingReopen?.cancel()
        pendingReopen = Task { [weak self, reopenDelay = timing.reopenDelay] in
            do {
                try await Task.sleep(for: reopenDelay)
            } catch {
                return
            }
            // 待機が終わってから MainActor に戻るまでの間に取り消された場合は何もしない
            guard !Task.isCancelled else { return }
            self?.reopen(attempt: attempt)
        }
    }

    private func reopen(attempt: Int) {
        pendingReopen = nil
        guard isRunning, fileSource == nil else { return }
        if openFileSource() {
            // 置き換わった内容を読み込み直す
            scheduleChange()
        } else if attempt < timing.maxReopenAttempts {
            scheduleReopen(attempt: attempt + 1)
        } else {
            // 諦める。読み込み直してファイルが無いことを公開し、再作成はディレクトリの監視で拾う
            scheduleChange()
        }
    }

    private func scheduleChange() {
        pendingChange?.cancel()
        pendingChange = Task { [weak self, debounceInterval = timing.debounceInterval] in
            do {
                try await Task.sleep(for: debounceInterval)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.notifyChange()
        }
    }

    private func notifyChange() {
        pendingChange = nil
        guard isRunning else { return }
        onChange()
    }
}
