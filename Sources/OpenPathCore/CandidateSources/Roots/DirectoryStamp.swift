import Darwin

/// ディレクトリ 1 つの、変化を見分けるための状態（Issue #78）。`stat` 1 回で読む。
///
/// - 更新日時（mtime）は、直下の項目の追加・削除・改名で変わる
/// - 状態変更日時（ctime）は、それに加えて権限・フラグ（隠し属性など）の変更でも変わる
/// - デバイスと inode は、同じパスのディレクトリが作り直された・シンボリックリンクの行き先が替わったときに変わる
///
/// 中のファイルの内容の変更では変わらない。候補（パスと種別）はディレクトリの一覧だけで決まるため、それで足りる。
struct DirectoryStamp: Sendable, Equatable {
    private static let nanosecondsPerSecond: Int64 = 1_000_000_000

    let device: Int32
    let inode: UInt64
    let modification: Int64
    let statusChange: Int64

    /// `path` の状態。シンボリックリンクはリンク先の状態を読む。存在しない・読めないときは nil。
    static func read(atPath path: String) -> DirectoryStamp? {
        var info = stat()
        guard stat(path, &info) == 0 else {
            return nil
        }
        return DirectoryStamp(
            device: info.st_dev,
            inode: info.st_ino,
            modification: nanoseconds(info.st_mtimespec),
            statusChange: nanoseconds(info.st_ctimespec)
        )
    }

    private static func nanoseconds(_ time: timespec) -> Int64 {
        Int64(time.tv_sec) * nanosecondsPerSecond + Int64(time.tv_nsec)
    }
}
