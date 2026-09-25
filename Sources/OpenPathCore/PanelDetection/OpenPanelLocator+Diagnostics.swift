/// `OpenPanelLocator` の診断（debug ログ、Issue #83）の記録。`pendingDiagnostics` が non-nil の locate の呼び出しの間だけ記録する。
extension OpenPanelLocator {
    /// 診断中だけ、候補のウィンドウの AXIdentifier も読む（ログに出すため）。失敗しても候補の判定には使わない。
    mutating func diagnosticIdentifier<Reader: PanelTreeReader>(
        of window: Node,
        reader: Reader
    ) -> String? where Reader.Node == Node {
        if let cached = entries[window]?.identifier {
            return cached.value
        }
        guard pendingDiagnostics != nil else { return nil }
        pendingDiagnostics?.diagnosticReadCount += 1
        guard let identifier = try? reader.identifier(of: window) else { return nil }
        entries[window]?.identifier = CachedAttribute(value: identifier)
        return identifier
    }

    /// 候補でないトップレベルのウィンドウを、診断中なら初めて見たときだけ記録する。
    mutating func recordNonCandidate(_ window: Node, role: String?, subrole: String?, identifier: String?) {
        guard pendingDiagnostics != nil, entries[window]?.isNonCandidateReported == false else { return }
        entries[window]?.isNonCandidateReported = true
        pendingDiagnostics?.entries.append(OpenPanelDiagnostic(
            target: .window,
            role: role,
            subrole: subrole,
            identifier: identifier,
            candidateReason: nil,
            result: .notCandidate,
            attempt: 0,
            maxAttempts: configuration.maxRechecks + 1,
            details: nil
        ))
    }

    /// 候補を判定した結果を、診断中なら記録する。
    mutating func recordClassification<Reader: PanelTreeReader>(
        of candidate: Node,
        _ diagnosticTarget: CandidateDiagnosticTarget,
        _ classification: OpenPanelClassification<Node>,
        result: OpenPanelDiagnostic.Result,
        attempt: Int,
        reader: Reader
    ) where Reader.Node == Node {
        guard pendingDiagnostics != nil else { return }
        let entry = entries[candidate]
        // シートのサブロール・AXIdentifier は判定に使わないため、診断のためだけに読む
        let subrole = entry?.subrole.map(\.value) ?? diagnosticRead { try reader.subrole(of: candidate) }
        let identifier = entry?.identifier.map(\.value) ?? diagnosticRead { try reader.identifier(of: candidate) }
        pendingDiagnostics?.diagnosticReadCount += classification.details?.diagnosticReadCount ?? 0
        pendingDiagnostics?.entries.append(OpenPanelDiagnostic(
            target: diagnosticTarget.target,
            role: entry?.role?.value,
            subrole: subrole,
            identifier: identifier,
            candidateReason: diagnosticTarget.reason,
            result: result,
            attempt: attempt,
            maxAttempts: configuration.maxRechecks + 1,
            details: classification.details
        ))
    }

    /// 診断のためだけの読み取り。回数を数え、失敗は nil にする。
    mutating func diagnosticRead(_ body: () throws -> String?) -> String? {
        pendingDiagnostics?.diagnosticReadCount += 1
        return (try? body()) ?? nil
    }
}
