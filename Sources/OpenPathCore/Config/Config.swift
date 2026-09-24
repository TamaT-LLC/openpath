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

// MARK: - 既定値（DSN-002 §6 のサンプルに従う。記入例である roots と disabled_apps は空にする）

public extension Config {
    /// 設定ファイルで roots を省略したときの値。空にする（サンプルの `~/repos` / `~/Documents` は環境によって存在しない）。
    ///
    /// 初回に生成するファイル（DefaultConfigFile）は ghq root、無ければ `~` を roots に明示して書く。
    /// 省略時の値をそれに合わせない理由:
    /// - 生成するファイルは roots を必ず書くため、省略されるのは利用者が消した・自分で書いた場合に限られ、その意図を優先する
    /// - ghq の有無で既定値を変えるには、デコードの中で ghq を実行する必要がある
    /// - `Config.default` は設定ファイルを読めない・生成できないときの設定でもあり、その状態でホーム全体の走査を始めない
    static let defaultRoots: [String] = []
    static let defaultDepth = 2
    static let defaultIncludeFiles = false
    /// 既定で自動確定しない（UX-001 §8）
    static let defaultAutoConfirm = false
    /// Ctrl+Shift+O（UX-001 §4, REQ-001 FR-PALETTE-05）
    static let defaultHotkey = Hotkey(key: .o, modifiers: [.control, .shift])
    /// 既定は全アプリで有効（REQ-001 FR-DETECT-04）。サンプルの `com.apple.finder` は記入例で既定値ではない
    static let defaultDisabledApps: Set<String> = []
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
