import Foundation

/// 1 つのファイル（またはディレクトリ）を `DispatchSource.makeFileSystemObjectSource` で監視する。
///
/// パスではなく開いたファイル記述子（inode）を監視するため、rename や削除で置き換わったファイルは追えない。
/// 置き換えへの追従は ConfigFileMonitor が開き直して行う。
/// 破棄時に監視を止めてファイル記述子を閉じる。
final class FileSystemEventSource {
    typealias Handler = @MainActor @Sendable (DispatchSource.FileSystemEvent) -> Void

    private let source: any DispatchSourceFileSystemObject

    /// パスを開いて監視を始める。開けなければ（存在しない等）nil。
    /// - Parameter handler: メインスレッドで呼ぶ。受け取るのは発生したイベントの集合
    init?(url: URL, eventMask: DispatchSource.FileSystemEvent, handler: @escaping Handler) {
        // 監視のためだけに開く。読み書きの権限を要求せず、ボリュームのアンマウントも妨げない
        let fileDescriptor = open(url.path(percentEncoded: false), O_EVTONLY)
        guard fileDescriptor >= 0 else { return nil }

        // 受け取った側がすぐに MainActor の状態を扱えるよう、メインキューで配送する
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: eventMask,
            queue: .main
        )
        source.setEventHandler { [weak source] in
            guard let event = source?.data else { return }
            MainActor.assumeIsolated {
                handler(event)
            }
        }
        source.setCancelHandler {
            close(fileDescriptor)
        }
        source.resume()
        self.source = source
    }

    deinit {
        cancel()
    }

    /// 監視を止める。以降ハンドラは呼ばれない。DispatchSource の cancel は冪等なので何度呼んでもよい
    func cancel() {
        source.cancel()
    }
}
