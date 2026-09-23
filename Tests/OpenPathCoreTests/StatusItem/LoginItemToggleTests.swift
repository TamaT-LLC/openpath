import Foundation
import Testing

import OpenPathCore

@Suite("ログイン時に起動: 切り替え（FR-CONFIG-03）")
struct LoginItemToggleTests {
    static let failure = NSError(
        domain: "SMAppServiceErrorDomain",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"]
    )

    // MARK: - 成功

    @Test("未登録なら登録し、登録後の状態を返す", arguments: [LoginItemStatus.notRegistered, .notFound])
    func registersWhenNotRegistered(initial: LoginItemStatus) {
        let registrar = LoginItemRegistrarFake(status: initial)

        let result = LoginItemToggle.perform(using: registrar)

        #expect(result == LoginItemToggleResult(outcome: .completed, status: .enabled))
        #expect(registrar.calls == [.register])
    }

    @Test("登録済みなら解除し、解除後の状態を返す")
    func unregistersWhenEnabled() {
        let registrar = LoginItemRegistrarFake(status: .enabled)

        let result = LoginItemToggle.perform(using: registrar)

        #expect(result == LoginItemToggleResult(outcome: .completed, status: .notRegistered))
        #expect(registrar.calls == [.unregister])
    }

    @Test("承認待ちで選んだら登録を取り消す")
    func unregistersWhenRequiresApproval() {
        let registrar = LoginItemRegistrarFake(status: .requiresApproval)

        let result = LoginItemToggle.perform(using: registrar)

        #expect(result == LoginItemToggleResult(outcome: .completed, status: .notRegistered))
        #expect(registrar.calls == [.unregister])
    }

    // MARK: - 承認待ち

    @Test("登録後に承認待ちになったら、システム設定のログイン項目を開いて許可を促す")
    func opensSystemSettingsWhenApprovalIsRequired() {
        let registrar = LoginItemRegistrarFake(status: .notRegistered)
        registrar.statusAfterRegister = .requiresApproval

        let result = LoginItemToggle.perform(using: registrar)

        #expect(result == LoginItemToggleResult(outcome: .needsApproval, status: .requiresApproval))
        #expect(registrar.calls == [.register, .openSystemSettings])
    }

    @Test("利用者がシステム設定で無効にしていて登録に失敗した場合も、承認待ちとして扱う")
    func treatsDeniedRegistrationAsNeedsApproval() {
        let registrar = LoginItemRegistrarFake(status: .notRegistered)
        registrar.registerError = Self.failure
        registrar.statusAfterRegister = .requiresApproval

        let result = LoginItemToggle.perform(using: registrar)

        #expect(result == LoginItemToggleResult(outcome: .needsApproval, status: .requiresApproval))
        #expect(registrar.calls == [.register, .openSystemSettings])
    }

    // MARK: - 失敗

    @Test("登録に失敗したら理由を返し、読み直した状態でチェックを戻す")
    func registrationFailure() {
        let registrar = LoginItemRegistrarFake(status: .notRegistered)
        registrar.registerError = Self.failure

        let result = LoginItemToggle.perform(using: registrar)

        let expectedError = LoginItemError(command: .register, underlying: Self.failure)
        #expect(result == LoginItemToggleResult(outcome: .failed(expectedError), status: .notRegistered))
        #expect(registrar.calls == [.register])
    }

    @Test("解除に失敗したら理由を返し、読み直した状態でチェックを戻す")
    func unregistrationFailure() {
        let registrar = LoginItemRegistrarFake(status: .enabled)
        registrar.unregisterError = Self.failure

        let result = LoginItemToggle.perform(using: registrar)

        let expectedError = LoginItemError(command: .unregister, underlying: Self.failure)
        #expect(result == LoginItemToggleResult(outcome: .failed(expectedError), status: .enabled))
        #expect(registrar.calls == [.unregister])
    }

    @Test(".app として起動していなければ何も呼ばない")
    func unavailableDoesNothing() {
        let registrar = LoginItemRegistrarFake(status: .unavailable)

        let result = LoginItemToggle.perform(using: registrar)

        #expect(result == LoginItemToggleResult(outcome: .unavailable, status: .unavailable))
        #expect(registrar.calls.isEmpty)
    }
}

@Suite("ログイン時に起動: 失敗の説明")
struct LoginItemErrorTests {
    static let failure = LoginItemToggleTests.failure

    @Test("登録の失敗は、有効にできなかったことと理由を説明する")
    func registrationDescription() {
        let error = LoginItemError(command: .register, underlying: Self.failure)

        #expect(error.description == "ログイン時に起動を有効にできませんでした（Operation not permitted）")
    }

    @Test("解除の失敗は、無効にできなかったことと理由を説明する")
    func unregistrationDescription() {
        let error = LoginItemError(command: .unregister, underlying: Self.failure)

        #expect(error.description == "ログイン時に起動を無効にできませんでした（Operation not permitted）")
    }

    @Test("ログ用の要約はドメインとコードだけにし、メッセージを含めない（NFR-05）")
    func logSummaryExcludesMessage() {
        let error = LoginItemError(command: .register, underlying: Self.failure)

        #expect(error.logSummary == "register SMAppServiceErrorDomain 1")
        #expect(!error.logSummary.contains("Operation not permitted"))
    }
}
