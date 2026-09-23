import OpenPathCore

/// GoToFolderPasteSequencer とテストダブル一式を組み立てる。
@MainActor
final class SequencerHarness {
    /// MainActor に積まれた後続ジョブを先に走らせるための譲り回数（CoordinatorHarness と同じ考え方）。
    private static let drainIterations = 20

    let clock = VirtualClock()
    let log: InjectionEventLog
    let pasteboard: FakePasteboard
    let keyboard: KeyboardSpy
    let sheetDetector: SheetDetectorFake
    let targetGuard: TargetGuardFake
    let hooks: HooksSpy
    let sequencer: GoToFolderPasteSequencer

    /// - Parameters:
    ///   - sheetAppearsAt: この経過時間以降の判定で移動先シートが出たことにする。nil なら出ない。
    ///   - clipboard: 注入前にユーザーがコピーしていた内容。
    init(sheetAppearsAt: Duration? = .milliseconds(150), clipboard: PasteboardSnapshot = .userClipboard) {
        let log = InjectionEventLog(clock: clock)
        let pasteboard = FakePasteboard(contents: clipboard)
        pasteboard.onWrite = { log.record(.pasteboardWrite($0)) }
        self.log = log
        self.pasteboard = pasteboard
        keyboard = KeyboardSpy(log: log)
        sheetDetector = SheetDetectorFake(clock: clock, log: log, appearsAt: sheetAppearsAt)
        targetGuard = TargetGuardFake(log: log)
        hooks = HooksSpy(clock: clock, log: log)
        sequencer = GoToFolderPasteSequencer(
            pasteboard: pasteboard,
            keyboard: keyboard,
            sheetDetector: sheetDetector,
            targetGuard: targetGuard,
            hooks: hooks.hooks,
            timing: .standard,
            clock: clock
        )
    }

    func run(path: String, autoConfirm: Bool = false) async throws {
        try await sequencer.run(path: path, autoConfirm: autoConfirm)
    }

    /// 別の Task で注入を始める（外からのキャンセルを試すため）。
    func startRun(path: String, autoConfirm: Bool = false) -> Task<Void, any Error> {
        Task { [sequencer] in
            try await sequencer.run(path: path, autoConfirm: autoConfirm)
        }
    }

    /// 「まだ何も起きていないこと」を確かめる前に、保留中の MainActor ジョブを処理させる。
    func drainMainActor() async {
        for _ in 0..<Self.drainIterations {
            await Task.yield()
        }
    }
}
