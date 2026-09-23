/// 設定ファイルが無いときに生成する config.toml の内容（UX-001 §7, DSN-002 §6）。
///
/// 値は `Config` の既定値から作るため、読み戻すと roots 以外は既定の Config になる。
/// 利用者が手で編集する前提のため、DSN-002 §6 のキーをすべて書き、それぞれに説明のコメントを付ける。
public enum DefaultConfigFile {
    private static let homeDirectoryPrefix = "~"
    private static let pathSeparator = "/"

    /// - Parameters:
    ///   - ghqRoot: `ghq root` の結果。絶対パスに解決できなければ、生成したファイルが読めなくならないよう roots に含めない
    ///   - homeDirectory: ホーム配下の ghq root を `~` で書くための基準。ConfigDecoder の `~` の展開先と同じ値を渡す
    public static func contents(ghqRoot: String?, homeDirectory: String) -> String {
        let roots = defaultRoots(ghqRoot: ghqRoot, homeDirectory: homeDirectory)
        let disabledApps = Config.defaultDisabledApps.sorted()
        return """
            # openpath の設定ファイル
            # 保存すると自動で読み込み直します。誤りがあるときは直前の設定のまま動作します。

            # 候補として走査するディレクトリ。~ はホームディレクトリを表します
            # 例: roots = ["~/repos", "~/Documents"]
            roots = \(TOMLLiteral.stringArray(roots))

            # roots を走査する深さ（0 以上）
            depth = \(Config.defaultDepth)

            # ディレクトリに加えてファイルも候補に含めるか（パネルがファイル選択か推定できないときに使います）
            include_files = \(Config.defaultIncludeFiles)

            # パスを入力した後に「開く」まで自動で押すか
            auto_confirm = \(Config.defaultAutoConfirm)

            # パレットを再表示するグローバルホットキー。修飾キー（ctrl / opt / shift / cmd）とキーを + でつなぎます
            hotkey = \(TOMLLiteral.string(Config.defaultHotkey.description))

            # パレットを出さないアプリの bundle id
            # 例: disabled_apps = ["com.apple.finder"]
            disabled_apps = \(TOMLLiteral.stringArray(disabledApps))

            # roots の走査で除外するディレクトリ名
            ignore = \(TOMLLiteral.stringArray(Config.defaultIgnore))

            [ghq]
            # ghq 管理下のリポジトリ（ghq list -p）を候補に含めるか
            enabled = \(GhqConfig.defaultEnabled)

            """
    }

    /// ghq root を正規化した絶対パスにし、ホーム配下なら `~` で書いた roots
    private static func defaultRoots(ghqRoot: String?, homeDirectory: String) -> [String] {
        let resolver = RootPathResolver(homeDirectory: homeDirectory)
        guard let ghqRoot, let resolvedRoot = resolver.resolve(ghqRoot) else { return [] }
        return [abbreviatingHomeDirectory(in: resolvedRoot, homeDirectory: resolver.resolve(homeDirectory))]
    }

    /// dotfiles で別のマシンと共有しても使えるよう、ホーム配下のパスは `~` で書く
    private static func abbreviatingHomeDirectory(in path: String, homeDirectory: String?) -> String {
        guard let homeDirectory, homeDirectory != pathSeparator else { return path }
        if path == homeDirectory {
            return homeDirectoryPrefix
        }
        let homeDirectoryWithSeparator = homeDirectory + pathSeparator
        guard path.hasPrefix(homeDirectoryWithSeparator) else { return path }
        return homeDirectoryPrefix + pathSeparator + String(path.dropFirst(homeDirectoryWithSeparator.count))
    }
}
