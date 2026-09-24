import Testing

import OpenPathCore

@Suite("OpenPanelLocator: 判定のキャッシュと読み取りの失敗")
struct OpenPanelLocatorCacheTests {
    private typealias Fixtures = PanelTreeFixtures
    private typealias Read = StubPanelTree.Read

    private static func documentWithSheet(_ sheet: StubNode) -> StubNode {
        Fixtures.documentWindow(id: "document", sheets: [sheet])
    }

    // MARK: - 設定

    @Test("既定の設定は 256 要素、250ms から倍々に 4 回まで判定し直す")
    func defaultConfiguration() {
        let configuration = OpenPanelCacheConfiguration()

        #expect(configuration.capacity == 256)
        #expect(configuration.initialRecheckDelay == .milliseconds(250))
        #expect(configuration.maxRechecks == 4)
    }

    @Test("容量と判定し直す回数の負の値は 0 として扱う")
    func negativeValuesAreClamped() {
        let configuration = OpenPanelCacheConfiguration(capacity: -1, maxRechecks: -1)

        #expect(configuration.capacity == 0)
        #expect(configuration.maxRechecks == 0)
    }

    // MARK: - キャッシュによる AX 呼び出しの削減

    @Test("ダイアログのパネルは、2 回目以降は矩形の読み取り 1 回だけで済む")
    func cachedDialogPanelCostsOneRead() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.dialog(id: "open", Fixtures.openPanelBody(.japanese)))
        _ = harness.locate(window)
        harness.tree.resetReads()

        _ = harness.locate(window, at: .milliseconds(200))

        #expect(harness.tree.reads == [Read(element: window, attribute: .frame)])
    }

    @Test("シートのパネルは、2 回目以降はウィンドウの子とシートの矩形の読み取り 2 回だけで済む")
    func cachedSheetPanelCostsTwoReads() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.documentWithSheet(Fixtures.remoteSheet(id: "sheet", Fixtures.openPanelBody(.english))))
        _ = harness.locate(window)
        harness.tree.resetReads()

        _ = harness.locate(window, at: .milliseconds(200))

        #expect(harness.tree.reads == [
            Read(element: window, attribute: .children),
            Read(element: StubElement("sheet"), attribute: .frame),
        ])
    }

    @Test("パネルのないウィンドウは、2 回目以降は子の読み取り 1 回だけで済む（ロールを覚えておく）")
    func windowWithoutPanelCostsOneRead() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.documentWindow(id: "document"))
        _ = harness.locate(window)
        harness.tree.resetReads()

        _ = harness.locate(window, at: .milliseconds(200))

        #expect(harness.tree.reads == [Read(element: window, attribute: .children)])
    }

    @Test("保存パネルは時間が経っても判定し直さない（確定的にパネルではない）")
    func savePanelIsNeverReclassified() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.documentWithSheet(Fixtures.sheet(id: "save", Fixtures.savePanelBody(.japanese))))
        _ = harness.locate(window)
        harness.tree.resetReads()

        #expect(harness.locate(window, at: .seconds(60)) == .notFound)
        #expect(!harness.didClassify(StubElement("save")))
    }

    // MARK: - 要素が欠けている候補の再判定

    @Test("確定ボタンかファイル一覧が欠けている候補は、250ms から倍々の間隔で 4 回まで判定し直す")
    func incompleteCandidateIsRecheckedWithBackoff() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.documentWithSheet(Fixtures.sheet(id: "alert", Fixtures.alertBody(.japanese))))
        let sheet = StubElement("alert")
        let schedule: [(elapsedMilliseconds: Int, expectsClassification: Bool)] = [
            (0, true),
            (249, false),
            (250, true),
            (749, false),
            (750, true),
            (1_749, false),
            (1_750, true),
            (3_749, false),
            (3_750, true),
            (60_000, false),
        ]

        for step in schedule {
            harness.tree.resetReads()
            #expect(harness.locate(window, at: .milliseconds(step.elapsedMilliseconds)) == .notFound)
            #expect(
                harness.didClassify(sheet) == step.expectsClassification,
                "\(step.elapsedMilliseconds)ms で判定したか"
            )
        }
    }

    @Test("描画途中だったシートのパネルも、判定し直したときに見つける（サンドボックスアプリ）")
    func loadingSheetIsFoundOnRecheck() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.documentWithSheet(Fixtures.sheet(id: "remote", [])))
        #expect(harness.locate(window) == .notFound)

        harness.tree.replace(Self.documentWithSheet(Fixtures.remoteSheet(id: "remote", Fixtures.openPanelBody(.japanese))))

        #expect(harness.locate(window, at: .milliseconds(100)) == .notFound)
        let panel = try #require(harness.panel(in: window, at: .milliseconds(250)))
        #expect(panel.element == StubElement("remote"))
        #expect(panel.isNewlyClassified)
    }

    @Test("判定し直す回数が 0 なら、要素が欠けている候補は 1 回の判定で確定する")
    func noRecheckWhenMaxRechecksIsZero() {
        let harness = OpenPanelLocatorHarness(configuration: OpenPanelCacheConfiguration(maxRechecks: 0))
        let window = harness.add(Self.documentWithSheet(Fixtures.sheet(id: "alert", Fixtures.alertBody(.english))))
        _ = harness.locate(window)
        harness.tree.resetReads()

        _ = harness.locate(window, at: .seconds(10))

        #expect(!harness.didClassify(StubElement("alert")))
    }

    // MARK: - 要素の破棄（kAXUIElementDestroyedNotification）

    @Test("破棄された要素の判定結果は忘れ、次は判定し直して新しい ID を振る")
    func forgottenPanelIsReclassified() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.dialog(id: "open", Fixtures.openPanelBody(.japanese)))
        let before = try #require(harness.panel(in: window))

        harness.locator.forget(window)
        let after = try #require(harness.panel(in: window, at: .milliseconds(200)))

        #expect(after.isNewlyClassified)
        #expect(after.context.id != before.context.id)
    }

    @Test("破棄された保存パネルは、次は判定し直す")
    func forgottenSavePanelIsReclassified() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.documentWithSheet(Fixtures.sheet(id: "save", Fixtures.savePanelBody(.english))))
        _ = harness.locate(window)

        harness.locator.forget(StubElement("save"))
        harness.tree.resetReads()
        _ = harness.locate(window, at: .milliseconds(200))

        #expect(harness.didClassify(StubElement("save")))
    }

    @Test("破棄された要素を忘れると、覚えている要素が減る。知らない要素なら何も起きない")
    func forgetRemovesEntry() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.dialog(id: "open", Fixtures.openPanelBody(.japanese)))
        _ = harness.locate(window)
        let countBefore = harness.locator.cachedElementCount

        harness.locator.forget(StubElement("unknown"))
        #expect(harness.locator.cachedElementCount == countBefore)
        harness.locator.forget(window)
        #expect(harness.locator.cachedElementCount == countBefore - 1)
    }

    // MARK: - 読み取りの失敗

    @Test("一時的に読めなかったら、そのウィンドウで直前に見つけたパネルを引き継ぐ（panelGone にしない）")
    func transientFailureKeepsLastKnownPanel() throws {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.documentWithSheet(Fixtures.sheet(id: "sheet", Fixtures.openPanelBody(.japanese))))
        let found = try #require(harness.panel(in: window))

        harness.tree.failures[window] = .unavailable
        let lookup = harness.locate(window, at: .milliseconds(200))

        let expected = LocatedOpenPanel(
            element: found.element,
            context: found.context,
            selectionEstimate: found.selectionEstimate,
            isNewlyClassified: false
        )
        #expect(lookup == .undetermined(lastKnown: expected))

        harness.tree.failures[window] = nil
        #expect(harness.panel(in: window, at: .milliseconds(400))?.context.id == found.context.id)
    }

    @Test("パネルを見つけていないウィンドウで読めなかったら、判定できなかったことだけを返す")
    func transientFailureWithoutPanel() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.documentWindow(id: "document"))
        _ = harness.locate(window)

        harness.tree.failures[window] = .unavailable

        #expect(harness.locate(window, at: .milliseconds(200)) == .undetermined(lastKnown: nil))
    }

    @Test("判定の途中で読めなかった結果は覚えず、次の走査ですぐに判定し直す")
    func failedClassificationIsNotCached() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.documentWithSheet(Fixtures.sheet(id: "sheet", Fixtures.openPanelBody(.japanese))))
        let sheet = StubElement("sheet")

        harness.tree.failures[sheet] = .unavailable
        #expect(harness.locate(window) == .undetermined(lastKnown: nil))

        harness.tree.failures[sheet] = nil
        #expect(harness.panel(in: window)?.element == sheet)
    }

    @Test("パネルが見つからなくなったら、以降の読み取りの失敗では古いパネルを引き継がない")
    func lastKnownPanelIsClearedWhenPanelCloses() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.documentWithSheet(Fixtures.sheet(id: "sheet", Fixtures.openPanelBody(.japanese))))
        _ = harness.locate(window)

        harness.tree.replace(Fixtures.documentWindow(id: "document"))
        #expect(harness.locate(window, at: .milliseconds(200)) == .notFound)
        harness.tree.failures[window] = .unavailable

        #expect(harness.locate(window, at: .milliseconds(400)) == .undetermined(lastKnown: nil))
    }

    @Test("破棄されたパネルは、読み取りの失敗時にも引き継がない")
    func forgottenPanelIsNotLastKnown() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.documentWithSheet(Fixtures.sheet(id: "sheet", Fixtures.openPanelBody(.japanese))))
        _ = harness.locate(window)

        harness.locator.forget(StubElement("sheet"))
        harness.tree.failures[window] = .unavailable

        #expect(harness.locate(window, at: .milliseconds(200)) == .undetermined(lastKnown: nil))
    }

    @Test("ウィンドウが破棄されていたらパネルなしとし、そのウィンドウを忘れる")
    func goneWindowIsNotFound() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Fixtures.dialog(id: "open", Fixtures.openPanelBody(.japanese)))
        _ = harness.locate(window)

        harness.tree.failures[window] = .elementGone

        #expect(harness.locate(window, at: .milliseconds(200)) == .notFound)
        #expect(harness.locator.cachedElementCount == 0)
    }

    @Test("子のシートが破棄されていたら、そのシートを飛ばして探す")
    func goneSheetIsSkipped() {
        let harness = OpenPanelLocatorHarness()
        let window = harness.add(Self.documentWithSheet(Fixtures.sheet(id: "sheet", Fixtures.openPanelBody(.japanese))))
        _ = harness.locate(window)

        harness.tree.failures[StubElement("sheet")] = .elementGone

        #expect(harness.locate(window, at: .milliseconds(200)) == .notFound)
    }

    // MARK: - 容量

    @Test("容量を超えたら、最後に使ってから長い要素から忘れる")
    func leastRecentlyUsedElementsAreEvicted() throws {
        let harness = OpenPanelLocatorHarness(configuration: OpenPanelCacheConfiguration(capacity: 3))
        let dialogs = ["a", "b", "c", "d"].map { harness.add(Fixtures.dialog(id: $0, Fixtures.openPanelBody(.japanese))) }
        let firstA = try #require(harness.panel(in: dialogs[0]))
        _ = harness.locate(dialogs[1])
        _ = harness.locate(dialogs[2])
        _ = harness.locate(dialogs[0])

        _ = harness.locate(dialogs[3])

        #expect(harness.locator.cachedElementCount == 3)
        #expect(harness.panel(in: dialogs[1])?.isNewlyClassified == true)
        let secondA = try #require(harness.panel(in: dialogs[0]))
        #expect(!secondA.isNewlyClassified)
        #expect(secondA.context.id == firstA.context.id)
    }

    @Test(
        "ほかのウィンドウの要素で容量を超えても、パネルの判定と直前のパネルは忘れない（1 回の走査でウィンドウごとに locate する）",
        arguments: ["dialog", "sheet"]
    )
    func panelSurvivesOtherWindowsInSameScan(panelKind: String) throws {
        let harness = OpenPanelLocatorHarness(configuration: OpenPanelCacheConfiguration(capacity: 3))
        let body = Fixtures.openPanelBody(.japanese)
        let panelWindow = harness.add(panelKind == "dialog"
            ? Fixtures.dialog(id: "panel-window", body)
            : Fixtures.documentWindow(id: "panel-window", sheets: [Fixtures.sheet(id: "sheet", body)]))
        let otherWindows = ["other-1", "other-2"].map { harness.add(Fixtures.documentWindow(id: $0)) }
        let first = try #require(harness.panel(in: panelWindow))

        for scan in 1...3 {
            let elapsed = Duration.milliseconds(200 * scan)
            for window in otherWindows {
                _ = harness.locate(window, at: elapsed)
            }
            harness.tree.failures[panelWindow] = .unavailable
            #expect(harness.locate(panelWindow, at: elapsed).panel?.context.id == first.context.id, "走査 \(scan) の引き継ぎ")
            harness.tree.failures[panelWindow] = nil
            let current = try #require(harness.panel(in: panelWindow, at: elapsed))
            #expect(current.context.id == first.context.id, "走査 \(scan)")
            #expect(!current.isNewlyClassified)
        }
    }

    @Test("パネルの判定も、それだけで容量を超えたら最後に使ってから長いものから忘れる（破棄の通知を取りこぼした場合）")
    func panelVerdictsAreStillBounded() throws {
        let harness = OpenPanelLocatorHarness(configuration: OpenPanelCacheConfiguration(capacity: 2))
        let dialogs = ["a", "b", "c"].map { harness.add(Fixtures.dialog(id: $0, Fixtures.openPanelBody(.japanese))) }
        for dialog in dialogs {
            _ = harness.locate(dialog)
        }

        #expect(harness.locator.cachedElementCount == 2)
        #expect(harness.panel(in: dialogs[2])?.isNewlyClassified == false)
        #expect(harness.panel(in: dialogs[0])?.isNewlyClassified == true)
    }

    @Test("1 回の走査で容量より多くの要素を使っても、その走査で使った要素は忘れない（パネルの ID を保つ）")
    func elementsUsedInCurrentScanAreKept() throws {
        let harness = OpenPanelLocatorHarness(configuration: OpenPanelCacheConfiguration(capacity: 1))
        let window = harness.add(Self.documentWithSheet(Fixtures.sheet(id: "sheet", Fixtures.openPanelBody(.japanese))))
        let first = try #require(harness.panel(in: window))

        let second = try #require(harness.panel(in: window, at: .milliseconds(200)))

        #expect(second.context.id == first.context.id)
        #expect(!second.isNewlyClassified)
    }
}
