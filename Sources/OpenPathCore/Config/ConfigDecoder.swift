import Foundation

/// TOML の中間表現（`TOMLTable`）を `Config` に変換する。
///
/// - 未指定のキーは既定値で補う。
/// - 型不一致・範囲外などの値はキーパス付きの `ConfigDecodingError` にする。誤りが複数あっても結果が揺れないよう、
///   roots → depth → include_files → auto_confirm → hotkey → disabled_apps → ignore → ghq → favorites の順で最初の 1 件を報告する。
/// - 未知のキーはエラーにせず `ConfigWarning` として返す。
public struct ConfigDecoder: Sendable {
    private typealias TopLevelReader = ConfigTableReader<TopLevelConfigKey>

    private let rootPathResolver: RootPathResolver

    /// - Parameter homeDirectory: roots の `~` の展開先。テストでは任意のパスを注入する
    public init(homeDirectory: String = NSHomeDirectory()) {
        rootPathResolver = RootPathResolver(homeDirectory: homeDirectory)
    }

    /// 既知の値を順に検証し、省略値を補う。お気に入りの任意のキーは未知設定の警告に含めない。
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
        let favorites = try decodeFavorites(reader)

        let config = Config(
            roots: roots,
            depth: depth,
            includeFiles: includeFiles,
            autoConfirm: autoConfirm,
            hotkey: hotkey,
            disabledApps: disabledApps,
            ignore: ignore,
            ghq: ghq,
            favorites: favorites
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

    /// 引用符付きの別名をパスへ対応付ける。パスの重複や空の名前は黙って無視せず設定エラーにする。
    private func decodeFavorites(_ reader: TopLevelReader) throws(ConfigDecodingError) -> [Favorite] {
        guard let table = try reader.table(.favorites) else { return [] }
        var seenPaths: Set<String> = []
        var favorites: [Favorite] = []
        for (name, value) in table.sorted(by: { $0.key < $1.key }) {
            let key = "favorites.\(name)"
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ConfigDecodingError(key: key, kind: .emptyFavoriteName)
            }
            guard case .string(let path) = value else {
                throw ConfigDecodingError(key: key, kind: .typeMismatch(expected: .string, actual: ConfigValueType(of: value)))
            }
            guard let resolved = rootPathResolver.resolve(path) else {
                throw ConfigDecodingError(key: key, kind: .invalidRootPath(path))
            }
            guard seenPaths.insert(resolved).inserted else {
                throw ConfigDecodingError(key: key, kind: .duplicateFavoritePath(resolved))
            }
            favorites.append(Favorite(name: name, path: resolved))
        }
        return favorites
    }
}
