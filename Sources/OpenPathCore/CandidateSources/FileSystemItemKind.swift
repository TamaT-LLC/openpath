import Foundation

/// パス 1 件の、パネルから見た種別。
enum FileSystemItemKind: Equatable {
    case directory
    /// 通常ファイルと、NSOpenPanel が既定でファイルとして扱うパッケージ（`.app` 等）
    case file

    /// シンボリックリンクはリンク先の種別で判定する。存在しない（リンク切れを含む）なら nil。
    static func ofItem(atPath path: String) -> FileSystemItemKind? {
        var isDirectory: ObjCBool = false
        // fileExists はシンボリックリンクを辿るため、リンク切れは存在しない扱いになる
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return nil
        }
        guard isDirectory.boolValue else {
            return .file
        }
        // URL のリソース値はリンク自体の属性を返すため、リンク先に解決してから問い合わせる
        let resolved = URL(filePath: path, directoryHint: .isDirectory).resolvingSymlinksInPath()
        return isPackage(directoryAt: resolved) ? .file : .directory
    }

    /// ディレクトリがパッケージか。
    ///
    /// `isPackageKey` の問い合わせは LaunchServices を引くため重く、全ディレクトリに行うと 5,000 件の走査で
    /// 数百 ms 以上かかる。パッケージは拡張子で識別されるため、拡張子の無いディレクトリは問い合わせずに false とする。
    static func isPackage(directoryAt url: URL) -> Bool {
        guard !url.pathExtension.isEmpty else {
            return false
        }
        return (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
    }
}
