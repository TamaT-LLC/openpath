import Testing

import OpenPathCore

@Suite("キーの送り先と、⌘⇧G の代替（/）を送ってよいフォーカスの判定")
struct InjectionKeyRoutingTests {
    private static let target: Int32 = 501
    private static let panelService: Int32 = 777
    static let ownProcess: Int32 = 42

    @Test("フォーカス中の要素を持つプロセス（別プロセスが描くパネルのサービス）へ送る")
    func sendsToFocusedElementOwner() {
        let destination = InjectionKeyDestination.processID(
            targetProcessID: Self.target,
            focusedElementProcessID: Self.panelService,
            ownProcessID: Self.ownProcess
        )

        #expect(destination == Self.panelService)
    }

    @Test("フォーカス中の要素が注入先のアプリのものなら、注入先のアプリへ送る")
    func sendsToTargetWhenFocusIsInTarget() {
        let destination = InjectionKeyDestination.processID(
            targetProcessID: Self.target,
            focusedElementProcessID: Self.target,
            ownProcessID: Self.ownProcess
        )

        #expect(destination == Self.target)
    }

    @Test("フォーカス中の要素を読めない・プロセスが不正・自分自身なら、注入先のアプリへ送る", arguments: [nil, 0, -1, InjectionKeyRoutingTests.ownProcess] as [Int32?])
    func fallsBackToTarget(focusedElementProcessID: Int32?) {
        let destination = InjectionKeyDestination.processID(
            targetProcessID: Self.target,
            focusedElementProcessID: focusedElementProcessID,
            ownProcessID: Self.ownProcess
        )

        #expect(destination == Self.target)
    }

    @Test("送り先を決めた理由を、フォーカス中の要素のプロセスの読み取り結果ごとに区別する（Issue #29 の切り分け用）")
    func resolvesDestinationWithReason() {
        let service = InjectionKeyDestination.resolve(
            targetProcessID: Self.target, focusedElementProcessID: Self.panelService, ownProcessID: Self.ownProcess
        )
        let sameAsTarget = InjectionKeyDestination.resolve(
            targetProcessID: Self.target, focusedElementProcessID: Self.target, ownProcessID: Self.ownProcess
        )
        let unreadable = InjectionKeyDestination.resolve(
            targetProcessID: Self.target, focusedElementProcessID: nil, ownProcessID: Self.ownProcess
        )
        let own = InjectionKeyDestination.resolve(
            targetProcessID: Self.target, focusedElementProcessID: Self.ownProcess, ownProcessID: Self.ownProcess
        )

        #expect(service == .init(processID: Self.panelService, reason: .focusedElementInOtherProcess))
        #expect(sameAsTarget == .init(processID: Self.target, reason: .focusedElementInTarget))
        #expect(unreadable == .init(processID: Self.target, reason: .focusedElementUnavailable))
        #expect(own == .init(processID: Self.target, reason: .focusedElementInOwnProcess))
    }

    @Test("フォーカス中の要素のプロセスが不正（0 以下）なら、読めなかったものとして注入先へ送る", arguments: [0, -1] as [Int32])
    func treatsInvalidProcessIDAsUnavailable(focusedElementProcessID: Int32) {
        let resolution = InjectionKeyDestination.resolve(
            targetProcessID: Self.target, focusedElementProcessID: focusedElementProcessID, ownProcessID: Self.ownProcess
        )

        #expect(resolution == .init(processID: Self.target, reason: .focusedElementUnavailable))
    }

    @Test(
        "ファイル一覧（カラム表示の列・アイコン表示の AXList、リスト表示の AXOutline・AXTable、ブラウザ）にフォーカスがあれば / を送ってよい",
        arguments: ["AXList", "AXOutline", "AXTable", "AXBrowser"]
    )
    func fileListRoles(role: String) {
        #expect(InjectionFocusedElement.classify(role: role) == .fileList)
    }

    @Test(
        "入力欄（検索欄はサブロールが AXSearchField の AXTextField）にフォーカスがあれば / は文字として入るため送らない",
        arguments: ["AXTextField", "AXTextArea", "AXComboBox"]
    )
    func textInputRoles(role: String) {
        #expect(InjectionFocusedElement.classify(role: role) == .textInput)
    }

    @Test("ファイル一覧でも入力欄でもない要素は other", arguments: ["AXButton", "AXWindow", "AXGroup", "AXWebArea", "AXRow", "AXSheet"])
    func otherRoles(role: String) {
        #expect(InjectionFocusedElement.classify(role: role) == .other)
    }

    @Test("ロールを読めなければ unavailable")
    func unreadableRole() {
        #expect(InjectionFocusedElement.classify(role: nil) == .unavailable)
    }
}
