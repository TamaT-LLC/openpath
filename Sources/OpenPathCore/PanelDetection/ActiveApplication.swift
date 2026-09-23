/// 最前面になったアプリ。PanelWatcher がどのアプリを観測するかの判断材料。
/// Core に AppKit を持ち込まないため、`NSRunningApplication` から必要な値だけを取り出して持つ。
public struct ActiveApplication: Equatable, Sendable {
    /// プロセス ID（`pid_t`）。
    public let processID: Int32
    /// bundle id。バンドルを持たないプロセスでは nil（`disabled_apps` と照合できないため常に観測対象）。
    public let bundleIdentifier: String?

    public init(processID: Int32, bundleIdentifier: String?) {
        self.processID = processID
        self.bundleIdentifier = bundleIdentifier
    }
}
