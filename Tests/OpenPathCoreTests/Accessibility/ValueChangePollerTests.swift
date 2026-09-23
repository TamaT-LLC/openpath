import Testing

import OpenPathCore

@Suite("ValueChangePoller")
struct ValueChangePollerTests {
    private static let permissionPollingInterval: Duration = .seconds(5)
    private static let neverEndingSleep: Duration = .seconds(3_600)
    private static let shortInterval: Duration = .milliseconds(1)

    /// 用意した値を順に返す読み取り元。待機と読み取りを発生順に記録する。
    /// 値が尽きた後の待機で CancellationError を投げ、ポーリングを終わらせる（テストを決定的にするため）。
    private actor ScriptedSource {
        enum Event: Equatable {
            case sleep(Duration)
            case read(Bool)
        }

        private var remainingValues: [Bool]
        private(set) var events: [Event] = []

        init(_ values: [Bool]) {
            remainingValues = values
        }

        func sleep(for duration: Duration) throws {
            events.append(.sleep(duration))
            if remainingValues.isEmpty {
                throw CancellationError()
            }
        }

        func read() -> Bool {
            guard !remainingValues.isEmpty else {
                Issue.record("用意した値が尽きた後に読み取られた")
                return false
            }
            let value = remainingValues.removeFirst()
            events.append(.read(value))
            return value
        }
    }

    private static func makePoller(source: ScriptedSource) -> ValueChangePoller<Bool> {
        ValueChangePoller(
            interval: permissionPollingInterval,
            sleep: { try await source.sleep(for: $0) },
            read: { await source.read() }
        )
    }

    private static func collectAll(_ stream: AsyncStream<Bool>) async -> [Bool] {
        var received: [Bool] = []
        for await value in stream {
            received.append(value)
        }
        return received
    }

    @Test("前回値から変化したときだけ通知する")
    func notifiesOnlyOnChange() async {
        let source = ScriptedSource([false, true, true, false, false])
        let poller = Self.makePoller(source: source)

        let received = await Self.collectAll(poller.changes(from: false))

        #expect(received == [true, false])
    }

    @Test("初期値と同じ値が続く間は何も通知しない")
    func doesNotNotifyWhileUnchanged() async {
        let source = ScriptedSource([false, false, false])
        let poller = Self.makePoller(source: source)

        let received = await Self.collectAll(poller.changes(from: false))

        #expect(received.isEmpty)
    }

    @Test("読み取りの前に毎回 interval だけ待つため、変化は interval 以内の次のポーリングで検知される")
    func waitsIntervalBeforeEachRead() async {
        let source = ScriptedSource([false, true])
        let poller = Self.makePoller(source: source)

        let received = await Self.collectAll(poller.changes(from: false))

        #expect(received == [true])
        let interval = Self.permissionPollingInterval
        #expect(await source.events == [
            .sleep(interval), .read(false),
            .sleep(interval), .read(true),
            .sleep(interval),
        ])
    }

    @Test("購読をやめると待機中のポーリングを止める", .timeLimit(.minutes(1)))
    func stopsPollingWhenConsumerCancels() async {
        let (sleepStarted, sleepStartedContinuation) = AsyncStream<Void>.makeStream()
        let (sleepCancelled, sleepCancelledContinuation) = AsyncStream<Void>.makeStream()
        let poller = ValueChangePoller<Bool>(
            interval: Self.permissionPollingInterval,
            sleep: { _ in
                sleepStartedContinuation.yield()
                do {
                    try await Task.sleep(for: Self.neverEndingSleep)
                } catch {
                    sleepCancelledContinuation.yield()
                    throw error
                }
            },
            read: { true }
        )
        let stream = poller.changes(from: false)
        let consumer = Task {
            for await _ in stream {}
        }

        var startedIterator = sleepStarted.makeAsyncIterator()
        _ = await startedIterator.next()
        consumer.cancel()

        var cancelledIterator = sleepCancelled.makeAsyncIterator()
        let cancelled: Void? = await cancelledIterator.next()
        #expect(cancelled != nil)
    }

    @Test("sleep を省略すると実時間で待機してポーリングする", .timeLimit(.minutes(1)))
    func usesTaskSleepByDefault() async {
        let poller = ValueChangePoller<Bool>(interval: Self.shortInterval, read: { true })

        var firstChange: Bool?
        for await value in poller.changes(from: false) {
            firstChange = value
            break
        }

        #expect(firstChange == true)
    }
}
