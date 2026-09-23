import Observation
import Testing

import OpenPathCore

@MainActor
@Suite("ObservationRelay", .timeLimit(.minutes(1)))
struct ObservationRelayTests {
    @MainActor
    @Observable
    final class Model {
        var value = 0
        var unrelated = ""
    }

    @MainActor
    final class Received {
        private(set) var values: [Int] = []

        func append(_ value: Int) {
            values.append(value)
        }
    }

    private let model = Model()
    private let received = Received()

    private func makeRelay() -> ObservationRelay<Int> {
        let model = model
        let received = received
        return ObservationRelay(read: { model.value }) { value in
            received.append(value)
        }
    }

    @Test("生成時に現在の値を渡す")
    func deliversInitialValue() {
        model.value = 3

        let relay = makeRelay()

        #expect(received.values == [3])
        relay.cancel()
    }

    @Test("値が変わるたびに新しい値を渡す")
    func deliversChanges() async {
        let relay = makeRelay()

        model.value = 1
        await MainActorQueue.waitUntil { received.values == [0, 1] }
        model.value = 2
        await MainActorQueue.waitUntil { received.values == [0, 1, 2] }

        #expect(received.values == [0, 1, 2])
        relay.cancel()
    }

    @Test("同じ値の代入や、読んでいないプロパティの変更では渡さない")
    func ignoresUnchangedValues() async {
        let relay = makeRelay()

        model.value = 0
        model.unrelated = "changed"
        await MainActorQueue.drain()

        #expect(received.values == [0])
        relay.cancel()
    }

    @Test("続けて変わった場合は最新の値を渡す")
    func coalescesRapidChanges() async {
        let relay = makeRelay()

        model.value = 1
        model.value = 2
        await MainActorQueue.waitUntil { received.values.last == 2 }

        #expect(received.values == [0, 2])
        relay.cancel()
    }

    @Test("cancel() の後は渡さない")
    func stopsAfterCancel() async {
        let relay = makeRelay()

        relay.cancel()
        model.value = 1
        await MainActorQueue.drain()

        #expect(received.values == [0])
    }
}
