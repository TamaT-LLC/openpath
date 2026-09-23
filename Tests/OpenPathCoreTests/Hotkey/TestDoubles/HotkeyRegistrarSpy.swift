import OpenPathCore

/// OS に触れずにホットキーの登録・解除を記録する HotkeyRegistering。
/// 登録ごとに連番のハンドルを返し、どの登録が解除されたかを検証できるようにする。
final class HotkeyRegistrarSpy: HotkeyRegistering {
    enum Call: Equatable {
        case register(Hotkey)
        case unregister(handle: Int)
    }

    /// 呼び出し順の記録。
    private(set) var calls: [Call] = []
    /// ここに含まれるホットキーの登録は、対応するエラーで失敗させる。
    var failures: [Hotkey: HotkeyRegistrationError] = [:]

    private var nextHandle = 1

    func register(_ hotkey: Hotkey) throws(HotkeyRegistrationError) -> Int {
        calls.append(.register(hotkey))
        if let failure = failures[hotkey] {
            throw failure
        }
        defer { nextHandle += 1 }
        return nextHandle
    }

    func unregister(_ registration: Int) {
        calls.append(.unregister(handle: registration))
    }

    /// これまでの記録を消す。前提となる操作の後、検証したい操作の呼び出しだけを見るために使う。
    func resetCalls() {
        calls.removeAll()
    }
}
