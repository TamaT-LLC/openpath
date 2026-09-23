/// ログイン時に起動の登録・解除の抽象（FR-CONFIG-03）。
/// Mac 層の SMAppService アダプタが実装し、テストでは OS に触れない偽物に差し替える。
///
/// スレッド安全は求めない。呼び出し元でスレッドを揃えること（Mac 層では MainActor から呼ぶ）。
public protocol LoginItemRegistering: AnyObject {
    /// 現在の登録状態。システム設定で利用者が変えることもあるため、読むたびに問い合わせる
    var status: LoginItemStatus { get }

    /// ログイン時に起動するよう登録する
    func register() throws

    /// 登録を解除する
    func unregister() throws

    /// システム設定の「一般 > ログイン項目」を開く。承認待ちのときに許可を促すために使う
    func openSystemSettings()
}
