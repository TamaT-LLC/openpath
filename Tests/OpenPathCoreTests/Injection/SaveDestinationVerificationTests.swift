import Foundation
import Testing
@testable import OpenPathCore

@Suite("保存先の実パス確認")
@MainActor
struct SaveDestinationVerificationTests {
    @Test(arguments: [nil, "folder", "/other/folder", "/expected/folder/child"] as [String?])
    func unavailableOrWrongLocationFails(observed: String?) async {
        let clock = VirtualClock()
        let target = TargetGuardFake(log: InjectionEventLog(clock: clock))
        var reads = 0
        let verifier = SaveDestinationVerification(clock: clock) { _ in
            reads += 1
            return observed
        }
        await #expect(throws: InjectionError.saveNavigationUnverified) {
            try await verifier.verify(path: "/expected/folder", targetGuard: target)
        }
        #expect(reads > 1)
        #expect(clock.elapsed <= .milliseconds(300))
    }

    @Test func waitsForUpdatedLocation() async throws {
        let clock = VirtualClock()
        let target = TargetGuardFake(log: InjectionEventLog(clock: clock))
        let verifier = SaveDestinationVerification(clock: clock) { _ in
            clock.elapsed < .milliseconds(100) ? "/previous" : "/expected/folder/"
        }
        try await verifier.verify(path: "/expected/folder", targetGuard: target)
        #expect(clock.elapsed == .milliseconds(100))
    }

    @Test func sameDirectoryThroughSymlinkMatches() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let alias = directory.appendingPathExtension("alias")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: alias)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
        let clock = VirtualClock()
        let target = TargetGuardFake(log: InjectionEventLog(clock: clock))
        let verifier = SaveDestinationVerification(clock: clock) { _ in directory.path }
        try await verifier.verify(path: alias.path, targetGuard: target)
    }

    @Test(arguments: [false, true])
    func readFailureOrTimeoutCannotSucceed(timesOut: Bool) async {
        let clock = VirtualClock()
        let target = TargetGuardFake(log: InjectionEventLog(clock: clock))
        let verifier = SaveDestinationVerification(clock: clock) { cutoff in
            if timesOut {
                clock.advance(by: .milliseconds(100))
                try cutoff.throwIfReached()
                return "/expected"
            }
            throw InjectionError.axError(code: -25204)
        }
        await #expect(throws: InjectionError.saveNavigationUnverified) {
            try await verifier.verify(path: "/expected", targetGuard: target)
        }
        #expect(clock.elapsed <= .milliseconds(300))
    }

    @Test func lateMatchingReadCannotSucceed() async {
        let clock = VirtualClock()
        let target = TargetGuardFake(log: InjectionEventLog(clock: clock))
        let verifier = SaveDestinationVerification(clock: clock) { _ in
            clock.advance(by: .milliseconds(301))
            return "/expected"
        }
        await #expect(throws: InjectionError.saveNavigationUnverified) {
            try await verifier.verify(path: "/expected", targetGuard: target)
        }
    }

    @Test func targetChangeDuringReadDoesNotSucceed() async {
        let clock = VirtualClock()
        let target = TargetGuardFake(log: InjectionEventLog(clock: clock))
        let verifier = SaveDestinationVerification(clock: clock) { _ in
            target.invalidation = (fromCheck: 0, status: .notFrontmost)
            return "/expected"
        }
        await #expect(throws: InjectionError.targetNotFrontmost) {
            try await verifier.verify(path: "/expected", targetGuard: target)
        }
    }

    @Test func cancellationDuringReadDoesNotSucceed() async {
        let clock = VirtualClock()
        let target = TargetGuardFake(log: InjectionEventLog(clock: clock))
        let verifier = SaveDestinationVerification(clock: clock) { _ in
            cancelCurrentTask()
            return "/expected"
        }
        let task = Task { try await verifier.verify(path: "/expected", targetGuard: target) }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
