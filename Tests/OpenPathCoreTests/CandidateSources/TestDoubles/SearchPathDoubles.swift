import OpenPathCore

/// 固定の検索パスを返し、問い合わせ回数を記録する SearchPathProviding。
actor SearchPathProviderSpy: SearchPathProviding {
    private let path: String
    private(set) var callCount = 0

    init(path: String) {
        self.path = path
    }

    func searchPath() async -> String {
        callCount += 1
        return path
    }
}

/// 指定したディレクトリが検索パスに含まれるときだけ、そこに実行ファイルがあるとみなす ExecutableLocating。
/// 実ファイルシステムに触れずに「未インストール」と「どの検索パスで探したか」を再現する。
struct StubExecutableLocator: ExecutableLocating {
    private static let searchPathSeparator: Character = ":"

    /// 実行ファイルがあるとみなすディレクトリ。nil なら常に見つからない（未インストール）。
    let installedDirectory: String?

    func locateExecutable(named name: String, inSearchPath searchPath: String) -> String? {
        guard let installedDirectory else { return nil }
        let directories = searchPath.split(separator: Self.searchPathSeparator).map(String.init)
        guard directories.contains(installedDirectory) else { return nil }
        return installedDirectory + "/" + name
    }
}
