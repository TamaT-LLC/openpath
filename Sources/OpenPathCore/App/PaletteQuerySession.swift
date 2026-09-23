/// パレットの候補の引き直し（検索語の変更・表示・候補の再構築）を、最新の要求の結果だけが残るように直列化する。
///
/// - 新しい要求のたびに前の要求の Task を取り消す。打鍵ごとのクエリを最後まで走らせない（DSN-002 §8）。
/// - 取り消しが間に合わずに前の要求の結果が後から届いても、世代で照合して捨てる。
///   CandidateIndex のクエリは取り消しを途中で確かめるが、確かめる前に終わった結果は返ってくるため。
/// - `CancellationError` は取り消しの結果なので何もしない。それ以外のエラーでは候補を変えない。
@MainActor
public final class PaletteQuerySession {
    /// 候補を引く。`CandidateIndex.query` の結果をパレットの行へ変換したものを返す。
    /// 呼び出し元（MainActor）ではなく並行実行用のスレッドで動かすため、隔離しない。
    public typealias Search = @Sendable (_ text: String, _ directoriesOnly: Bool, _ limit: Int) async throws -> [PaletteRow]
    /// 引いた候補をパレットへ反映する。
    public typealias Apply = @MainActor (_ rows: [PaletteRow], _ keepingSelection: Bool) -> Void

    /// 1 回に引く候補の上限。パレットは 8 行を超える分をスクロールさせるため表示行数より多く引くが、
    /// 表示直前の存在確認（stat）と行の描画が打鍵ごとに膨らまないよう抑える。
    public static let resultLimit = 50

    private let search: Search
    private let apply: Apply
    private let limit: Int
    /// 要求のたびに増やし、結果が最新の要求のものかを照合する
    private var generation = 0
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - limit: 1 回に引く候補の上限。
    ///   - search: 候補の引き方。
    ///   - apply: 最新の要求の結果の反映先。
    public init(limit: Int = resultLimit, search: @escaping Search, apply: @escaping Apply) {
        self.limit = limit
        self.search = search
        self.apply = apply
    }

    /// 前の要求を取り消し、`text` で候補を引き直す。
    /// - Parameters:
    ///   - directoriesOnly: ディレクトリだけを候補にするか。
    ///   - keepingSelection: 選択中の候補が結果に残っていれば選択を保つか（検索語を変えずに引き直す場合）。
    public func request(_ text: String, directoriesOnly: Bool, keepingSelection: Bool = false) {
        let requestGeneration = advanceGeneration()
        task = Task { [weak self, search, limit] in
            let rows: [PaletteRow]
            do {
                rows = try await search(text, directoriesOnly, limit)
            } catch is CancellationError {
                return
            } catch {
                // 検索語を含め得るため、エラーの型名だけを記録する
                Log.warning("候補を引けませんでした（\(type(of: error))）")
                return
            }
            self?.finish(generation: requestGeneration, rows: rows, keepingSelection: keepingSelection)
        }
    }

    /// 実行中の要求を取り消す。以降に届いた結果は反映しない（パレットを閉じたとき）。
    public func cancel() {
        advanceGeneration()
    }

    @discardableResult
    private func advanceGeneration() -> Int {
        task?.cancel()
        task = nil
        generation += 1
        return generation
    }

    private func finish(generation requestGeneration: Int, rows: [PaletteRow], keepingSelection: Bool) {
        guard requestGeneration == generation else { return }
        task = nil
        apply(rows, keepingSelection)
    }
}
