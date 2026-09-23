/// `~/.config/openpath/config.toml` の内容（DSN-002 §6）。`ConfigDecoder` で TOML から生成する。
public struct Config: Sendable, Equatable {
    /// 候補として走査するディレクトリ。`~` 展開と正規化を済ませた絶対パスで、重複は無い
    public let roots: [String]
    /// roots を走査する深さ（0 以上）
    public let depth: Int
    /// ファイルも候補に含めるか（パネルがファイル選択か推定できない場合に使う）
    public let includeFiles: Bool
    /// 移動後に「開く」まで自動で押すか
    public let autoConfirm: Bool
    /// パレットを再表示するグローバルホットキー
    public let hotkey: Hotkey
    /// パレットを出さないアプリの bundle id
    public let disabledApps: Set<String>
    /// roots の走査で除外するディレクトリ名
    public let ignore: [String]
    public let ghq: GhqConfig

    public init(
        roots: [String] = Config.defaultRoots,
        depth: Int = Config.defaultDepth,
        includeFiles: Bool = Config.defaultIncludeFiles,
        autoConfirm: Bool = Config.defaultAutoConfirm,
        hotkey: Hotkey = Config.defaultHotkey,
        disabledApps: Set<String> = Config.defaultDisabledApps,
        ignore: [String] = Config.defaultIgnore,
        ghq: GhqConfig = .default
    ) {
        self.roots = roots
        self.depth = depth
        self.includeFiles = includeFiles
        self.autoConfirm = autoConfirm
        self.hotkey = hotkey
        self.disabledApps = disabledApps
        self.ignore = ignore
        self.ghq = ghq
    }
}

// MARK: - 既定値（DSN-002 §6 のサンプルに従う）

public extension Config {
    /// サンプルの `~/repos` / `~/Documents` は環境によって存在しないため既定では空にする。
    /// 初回のファイル生成時に ConfigStore が `ghq root` などを書き込む想定
    static let defaultRoots: [String] = []
    static let defaultDepth = 2
    static let defaultIncludeFiles = false
    /// 既定で自動確定しない（UX-001 §8）
    static let defaultAutoConfirm = false
    /// Ctrl+Shift+O（UX-001 §4, REQ-001 FR-PALETTE-05）
    static let defaultHotkey = Hotkey(key: .o, modifiers: [.control, .shift])
    static let defaultDisabledApps: Set<String> = ["com.apple.finder"]
    static let defaultIgnore = ["node_modules", ".git", "target", "DerivedData", ".build"]

    /// すべてのキーが既定値の設定
    static let `default` = Config()
}

// MARK: - 値の制約

public extension Config {
    /// 負の走査深さは意味を持たないため、これを下回る値はデコードエラーにする
    static let minimumDepth = 0
}

/// `[ghq]` テーブルの設定
public struct GhqConfig: Sendable, Equatable {
    /// `ghq list -p` の結果を候補に含めるか
    public let enabled: Bool

    public init(enabled: Bool = GhqConfig.defaultEnabled) {
        self.enabled = enabled
    }
}

public extension GhqConfig {
    static let defaultEnabled = true
    static let `default` = GhqConfig()
}
