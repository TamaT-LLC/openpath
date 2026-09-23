import Testing

import OpenPathCore

@MainActor
@Suite("CandidateHistoryRecorder")
struct CandidateHistoryRecorderTests {
    /// 記録と、記録後の通知の順番を 1 本の列に残す。
    @MainActor
    final class EventLog: HistoryRecording {
        enum Event: Equatable {
            case record(String)
            case didRecord
        }

        private(set) var events: [Event] = []

        func record(path: String) {
            events.append(.record(path))
        }

        func didRecord() {
            events.append(.didRecord)
        }
    }

    @Test("確定したパスを履歴に記録してから、候補の履歴の取り直しを知らせる")
    func recordsThenNotifies() {
        let log = EventLog()
        let recorder = CandidateHistoryRecorder(store: log) { log.didRecord() }

        recorder.record(path: "/Users/example/repos/fern")
        recorder.record(path: "/Users/example/repos/openpath")

        #expect(log.events == [
            .record("/Users/example/repos/fern"),
            .didRecord,
            .record("/Users/example/repos/openpath"),
            .didRecord,
        ])
    }
}
