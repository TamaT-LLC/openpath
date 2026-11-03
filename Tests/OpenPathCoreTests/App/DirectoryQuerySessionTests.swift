import Testing
import OpenPathCore

@MainActor
@Suite("DirectoryQuerySession", .timeLimit(.minutes(1)))
struct DirectoryQuerySessionTests {
    @MainActor
    final class Results {
        var values: [DirectorySearchResult] = []
        var selections: [Bool] = []
    }
    private let loader = ScriptedDirectoryLoad()
    private let results = Results()
    private let session: DirectoryQuerySession
    private let tree: FileTreeFixture

    init() throws {
        tree = try FileTreeFixture()
        let results = results
        session = DirectoryQuerySession(load: loader.load) { result, keep in
            results.values.append(result)
            results.selections.append(keep)
        }
    }

    private func request(_ path: String = "/root", text: String = "", ignore: Set<String> = [], reload: Bool = false) {
        session.request(directory: path, text: text, ignoredNames: ignore, directoriesOnly: true, reload: reload)
    }

    @Test("読み込み中の打鍵で再列挙せず、最新の検索語だけを適用する")
    func typingSharesListing() async throws {
        try tree.makeDirectories("alpha", "beta")
        request(text: "a")
        await loader.waitForCalls(1)
        request(text: "bet")
        loader.respond(0, items: [.directory(tree.path("alpha")), .directory(tree.path("beta"))])
        await MainActorQueue.waitUntil { results.values.count == 1 }
        #expect(results.values[0].rows.map(\.name) == ["beta"])
        #expect(loader.paths.count == 1)
        #expect(loader.cancelled.isEmpty)
        request(text: "alpha")
        await MainActorQueue.waitUntil { results.values.count == 2 }
        #expect(results.values[1].rows.map(\.name) == ["alpha"])
        #expect(loader.paths.count == 1)
        session.cancel()
    }

    @Test("移動前の列挙が後から完了しても候補やメッセージを上書きしない")
    func dropsStaleListing() async {
        request("/old")
        await loader.waitForCalls(1)
        request("/new")
        await loader.waitForCalls(2)
        loader.respond(1, message: "new")
        await MainActorQueue.waitUntil { results.values.count == 1 }
        loader.respond(0, message: "old")
        await MainActorQueue.drain()
        #expect(results.values.map(\.message) == ["new"])
        #expect(loader.cancelled.contains(0))
        session.cancel()
    }

    @Test("閉じた後の結果を捨て、再度開くと前回の候補を使わず列挙し直す")
    func cancellationReleasesCachedListing() async {
        request()
        await loader.waitForCalls(1)
        session.cancel()
        loader.respond(0, message: "stale")
        await MainActorQueue.drain()
        #expect(results.values.isEmpty)
        request()
        await loader.waitForCalls(2)
        loader.respond(1, message: "fresh")
        await MainActorQueue.waitUntil { results.values.count == 1 }
        #expect(results.values[0].message == "fresh")
        session.cancel()
    }

    @Test("ignore の変更と明示的な再構築で列挙し直す")
    func optionsAndReloadInvalidateListing() async {
        request()
        await loader.waitForCalls(1)
        #expect(!session.isListed(directory: "/root", ignoredNames: []))
        loader.respond(0)
        await MainActorQueue.waitUntil { results.values.count == 1 }
        #expect(session.isListed(directory: "/root", ignoredNames: []))
        #expect(!session.isListed(directory: "/other", ignoredNames: []))
        #expect(!session.isListed(directory: "/root", ignoredNames: ["skip"]))
        request(ignore: ["skip"])
        #expect(!session.isListed(directory: "/root", ignoredNames: ["skip"]))
        await loader.waitForCalls(2)
        loader.respond(1)
        await MainActorQueue.waitUntil { results.values.count == 2 }
        request(ignore: ["skip"], reload: true)
        #expect(!session.isListed(directory: "/root", ignoredNames: ["skip"]))
        await loader.waitForCalls(3)
        #expect(loader.ignoredNames == [[], ["skip"], ["skip"]])
        loader.respond(2)
        await MainActorQueue.waitUntil { results.values.count == 3 }
        #expect(session.isListed(directory: "/root", ignoredNames: ["skip"]))
        session.cancel()
        #expect(!session.isListed(directory: "/root", ignoredNames: ["skip"]))
    }
}
