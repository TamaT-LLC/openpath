import Foundation

/// ログの出力先と出力条件。
public struct LogConfiguration: Sendable, Equatable {
    private static let bytesPerMebibyte = 1_024 * 1_024

    /// 既定の出力先 `~/Library/Logs/openpath`（NFR-05）。
    public static let defaultDirectory = URL.libraryDirectory
        .appending(path: "Logs", directoryHint: .isDirectory)
        .appending(path: AppInfo.name, directoryHint: .isDirectory)
    public static let defaultFileName = "\(AppInfo.name).log"
    /// 常駐アプリのためディスクを圧迫しないよう、ローテーション分を含めて 10MiB 程度に収める。
    public static let defaultMaximumFileSize = 5 * bytesPerMebibyte
    /// パスを含む debug ログは開発時のみ出力し、リリースビルドでは記録しない（NFR-05）。
    public static let defaultMinimumLevel: LogLevel = {
        #if DEBUG
        return .debug
        #else
        return .info
        #endif
    }()

    /// 最小レベルを既定から変える設定（UserDefaults `jp.tamat.openpath` のキー）。
    /// リリースビルドでも QA の切り分けのために debug ログ（パスを含む）を出せるようにする（Issue #74）。
    /// 有効化: `defaults write jp.tamat.openpath logLevel debug`、無効化: `defaults delete jp.tamat.openpath logLevel`（openpath の再起動後に反映）。
    public static let minimumLevelPreferenceKey = "logLevel"

    /// ローテーション時に退避するファイルの拡張子。1 世代のみ保持する。
    private static let rotatedFileExtension = "1"

    /// ログファイルを置くディレクトリ。存在しなければ最初の書き込み時に作成する。
    public var directory: URL
    public var fileName: String
    /// このサイズ（バイト）を超える書き込みの前に、既存ファイルを `.1` に退避する。
    public var maximumFileSize: Int
    /// これより低い重要度のログは出力しない。
    public var minimumLevel: LogLevel

    public var fileURL: URL {
        directory.appending(path: fileName, directoryHint: .notDirectory)
    }

    public var rotatedFileURL: URL {
        fileURL.appendingPathExtension(Self.rotatedFileExtension)
    }

    /// 設定値（`minimumLevelPreferenceKey` の値）から最小レベルを決める。
    /// 設定が無い・どのレベルにも当たらなければ既定の最小レベル（DEBUG ビルドで debug、リリースビルドで info）。
    public static func minimumLevel(preferenceValue: String?) -> LogLevel {
        preferenceValue.flatMap(LogLevel.init(preferenceValue:)) ?? defaultMinimumLevel
    }

    public init(
        directory: URL = LogConfiguration.defaultDirectory,
        fileName: String = LogConfiguration.defaultFileName,
        maximumFileSize: Int = LogConfiguration.defaultMaximumFileSize,
        minimumLevel: LogLevel = LogConfiguration.defaultMinimumLevel
    ) {
        self.directory = directory
        self.fileName = fileName
        self.maximumFileSize = maximumFileSize
        self.minimumLevel = minimumLevel
    }
}
