import Foundation

/// `history.json` の読み書き（DSN-002 §7, FR-HISTORY-04）。
///
/// 形式は `[HistoryEntry]` の JSON 配列で、`last_used` は UTC の ISO 8601（例: `2026-05-09T06:13:20Z`）。
/// frecency の減衰区間は 1 時間単位のため秒精度で十分とし、秒未満は切り捨てる。
/// 読み込めないファイルは `history.json.broken-<timestamp>` に退避し、次の保存で上書きしないようにする。
public struct HistoryFile: Sendable {
    public static let fileName = "history.json"

    /// 既定の保存先 `~/Library/Application Support/openpath`。
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: AppInfo.name, directoryHint: .isDirectory)
    }

    /// 履歴は開いたパスの一覧で個人の作業内容が分かるため、所有者以外から読めないようにする。
    private static let filePermissions = 0o600
    private static let directoryPermissions = 0o700
    private static let brokenFileInfix = ".broken-"
    /// 退避ファイル名に使う時刻。ファイル名に `:` を含めないよう ISO 8601 の基本形式（例: `20260509T061320Z`）にする。
    private static let brokenFileTimestampStyle = Date.ISO8601FormatStyle(
        dateSeparator: .omitted,
        dateTimeSeparator: .standard,
        timeSeparator: .omitted,
        timeZone: .gmt
    )

    public let directory: URL
    private let now: @Sendable () -> Date

    public var fileURL: URL {
        directory.appending(path: Self.fileName)
    }

    /// - Parameters:
    ///   - directory: 保存先。テストで実ユーザーのファイルに触れないよう、既定値を持たせず明示させる。
    ///   - now: 退避ファイル名の時刻に使う。
    public init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.now = now
    }

    public func load() -> HistoryLoadResult {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return .notFound
        } catch {
            return .corrupted(movedTo: moveBrokenFileAside())
        }

        do {
            return .loaded(try Self.makeDecoder().decode([HistoryEntry].self, from: data))
        } catch {
            return .corrupted(movedTo: moveBrokenFileAside())
        }
    }

    /// ディレクトリが無ければ 0700 で作り、`.atomic` で書き込んでから 0600 にする。
    /// `.atomic` は一時ファイルを rename するため新規作成時は既定の権限になる。書き込むたびに権限を設定し直す。
    public func save(_ entries: [HistoryEntry]) throws {
        let data = try Self.makeEncoder().encode(entries)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Self.directoryPermissions]
        )
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: Self.filePermissions],
            ofItemAtPath: fileURL.path(percentEncoded: false)
        )
    }

    /// 退避先の URL を返す。退避に失敗した場合は nil。
    private func moveBrokenFileAside() -> URL? {
        let timestamp = Self.brokenFileTimestampStyle.format(now())
        let backupURL = directory.appending(path: Self.fileName + Self.brokenFileInfix + timestamp)
        do {
            try FileManager.default.moveItem(at: fileURL, to: backupURL)
            return backupURL
        } catch {
            // TODO(#3): Log.warning で退避の失敗を記録する
            return nil
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // 手で確認・編集しやすいよう整形し、パスの `/` もエスケープしない
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// 読み書き自体はどのスレッドからでも行えるよう、MainActor の推論が型全体に及ばない extension で準拠させる
extension HistoryFile: HistoryPersisting {}
