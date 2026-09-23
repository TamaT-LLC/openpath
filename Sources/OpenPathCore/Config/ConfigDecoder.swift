import Foundation

/// TOML の中間表現（`TOMLTable`）を `Config` に変換する。
///
/// - 未指定のキーは既定値で補う。
/// - 型不一致・範囲外などの値はキーパス付きの `ConfigDecodingError` にする。誤りが複数あっても結果が揺れないよう、
///   roots → depth → include_files → auto_confirm → hotkey → disabled_apps → ignore → ghq の順で最初の 1 件を報告する。
/// - 未知のキーはエラーにせず `ConfigWarning` として返す。
public struct ConfigDecoder: Sendable {
    private typealias TopLevelReader = ConfigTableReader<TopLevelConfigKey>

    private let rootPathResolver: RootPathResolver

    /// - Parameter homeDirectory: roots の `~` の展開先。テストでは任意のパスを注入する
    public init(homeDirectory: String = NSHomeDirectory()) {
        rootPathResolver = RootPathResolver(homeDirectory: homeDirectory)
    }

    public func decode(_ table: TOMLTable) throws(ConfigDecodingError) -> ConfigDecodingResult {
        let reader = TopLevelReader(table: table)

        let roots = try decodeRoots(reader)
        let depth = try decodeDepth(reader)
        let includeFiles = try reader.bool(.includeFiles) ?? Config.defaultIncludeFiles
        let autoConfirm = try reader.bool(.autoConfirm) ?? Config.defaultAutoConfirm
        let hotkey = try decodeHotkey(reader)
        let disabledApps = try reader.stringArray(.disabledApps).map(Set.init) ?? Config.defaultDisabledApps
        let ignore = try reader.stringArray(.ignore) ?? Config.defaultIgnore
        let ghqReader = try reader.subtable(.ghq, keys: GhqConfigKey.self)
        let ghq = GhqConfig(enabled: try ghqReader?.bool(.enabled) ?? GhqConfig.defaultEnabled)

        let config = Config(
            roots: roots,
            depth: depth,
            includeFiles: includeFiles,
            autoConfirm: autoConfirm,
            hotkey: hotkey,
            disabledApps: disabledApps,
            ignore: ignore,
            ghq: ghq
        )
        let unknownKeyPaths = reader.unknownKeyPaths + (ghqReader?.unknownKeyPaths ?? [])
        return ConfigDecodingResult(config: config, warnings: unknownKeyPaths.sorted().map(ConfigWarning.unknownKey))
    }

    private func decodeRoots(_ reader: TopLevelReader) throws(ConfigDecodingError) -> [String] {
        guard let paths = try reader.stringArray(.roots) else { return Config.defaultRoots }

        var resolvedPaths: [String] = []
        var seenPaths: Set<String> = []
        for path in paths {
            guard let resolvedPath = rootPathResolver.resolve(path) else {
                throw reader.error(.roots, .invalidRootPath(path))
            }
            // 表記違いの同じディレクトリを二重に走査しないよう、正規化後に先勝ちで重複を除く
            if seenPaths.insert(resolvedPath).inserted {
                resolvedPaths.append(resolvedPath)
            }
        }
        return resolvedPaths
    }

    private func decodeDepth(_ reader: TopLevelReader) throws(ConfigDecodingError) -> Int {
        guard let depth = try reader.integer(.depth) else { return Config.defaultDepth }
        guard depth >= Config.minimumDepth else {
            throw reader.error(.depth, .belowMinimum(value: depth, minimum: Config.minimumDepth))
        }
        return depth
    }

    private func decodeHotkey(_ reader: TopLevelReader) throws(ConfigDecodingError) -> Hotkey {
        guard let source = try reader.string(.hotkey) else { return Config.defaultHotkey }
        do throws(HotkeyParseError) {
            return try HotkeyParser.parse(source)
        } catch {
            throw reader.error(.hotkey, .invalidHotkey(error))
        }
    }
}
