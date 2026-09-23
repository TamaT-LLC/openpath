/// MainActor 上で非同期に進む処理の待ち合わせ。
@MainActor
enum MainActorQueue {
    /// main キューは FIFO のため数回で足りるが、ジョブが数段連鎖しても足りるよう余裕を持たせる。
    private static let drainIterations = 20

    /// 「何も起きないこと」を確かめる前に、保留中の MainActor ジョブを処理させる。
    static func drain() async {
        for _ in 0..<drainIterations {
            await Task.yield()
        }
    }

    /// 条件を満たすまで MainActor を譲りながら待つ。
    /// 待つ相手が並行実行用のスレッドを経由して MainActor に戻る（候補の検索など）ため、回数では区切らない。
    /// 満たされない場合はスイートの時間制限で失敗させる。
    static func waitUntil(_ condition: () -> Bool) async {
        while !condition() {
            await Task.yield()
        }
    }
}
