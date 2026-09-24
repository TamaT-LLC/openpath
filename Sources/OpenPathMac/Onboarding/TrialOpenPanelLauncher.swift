import AppKit

import OpenPathCore

/// 「試してみる」で「開く」ダイアログを出す（UX-001 §7）。方式の理由は OpenPathCore の `TrialOpenPanelScript` を参照。
///
/// osascript は他のプロセスから起動されると自分では前面に出ないため、前面に出せる状態になるのを待って前面に出す
/// （待ち方と送り直しは OpenPathCore の `TrialPanelActivator`）。PanelWatcher は最前面のアプリだけを観測するので、
/// 前面に出ればパネルを検知してパレットが重なる。前面に出せなかった場合も、利用者がダイアログをクリックすれば
/// 同じように検知される（ダイアログの案内の文言にも書いてある）。
@MainActor
final class TrialOpenPanelLauncher {
    private var process: Process?
    private var activationTask: Task<Void, Never>?

    /// ダイアログを出す。前回のダイアログがまだ開いていれば、重ねて出さずに前面に出し直す。
    func launch() {
        if let process, process.isRunning {
            bringToFront(process)
            return
        }

        let process = Process()
        process.executableURL = URL(filePath: TrialOpenPanelScript.executablePath)
        process.arguments = TrialOpenPanelScript.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            // キャンセル（-128）でも終了コードは 0 以外になる。選ばれたフォルダは使わないため結果は記録するだけ
            let status = finished.terminationStatus
            Log.debug("「試してみる」のダイアログを閉じました（終了コード: \(status)）")
        }
        do {
            try process.run()
        } catch {
            // エラーの説明は実行ファイルのパスを含み得るため、ドメインとコードだけを記録する
            let nsError = error as NSError
            Log.warning("「試してみる」のダイアログを出せませんでした（\(nsError.domain) \(nsError.code)）")
            return
        }
        self.process = process
        Log.info("「試してみる」のダイアログを出しました")
        bringToFront(process)
    }

    /// 開いているダイアログを閉じる。アプリの終了時に呼び、osascript を残さない。
    func terminate() {
        activationTask?.cancel()
        activationTask = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
    }

    /// osascript が前面に出せる状態になるのを待って前面に出し、結果をログに残す。
    ///
    /// osascript は起動から 0.1 秒ほどで登録されるが、ダイアログを出す直前までは prohibited で、その間の要求は断られる
    /// （Issue #72: 登録を見つけた直後に 1 度だけ要求して諦めていた）。
    private func bringToFront(_ process: Process) {
        activationTask?.cancel()
        let processID = process.processIdentifier
        let activator = TrialPanelActivator(
            observe: { Self.state(of: process) },
            activate: { Self.requestActivation(processID: processID) }
        )
        activationTask = Task { @MainActor in
            guard let outcome = await activator.run() else { return }
            if outcome.needsUserAction {
                Log.warning(outcome.logMessage)
            } else {
                Log.info(outcome.logMessage)
            }
        }
    }

    private static func state(of process: Process) -> TrialPanelProcessState {
        guard process.isRunning else { return .exited }
        let processID = process.processIdentifier
        guard let application = NSRunningApplication(processIdentifier: processID) else { return .notRegistered }
        if application.isTerminated {
            return .exited
        }
        if application.isActive || NSWorkspace.shared.frontmostApplication?.processIdentifier == processID {
            return .active
        }
        // ダイアログを出す直前に UIElement（accessory）へ変わり、前面に出せるようになる
        return application.activationPolicy == .prohibited ? .backgroundOnly : .inactive
    }

    /// 前面に出す要求を送る。macOS 14 以降の協調的なアクティブ化の API（activate(from:)）を先に使い、
    /// 断られたら従来の API でも頼む（macOS 27 ではどちらも、openpath がアクティブでなくても受け付けられた）。
    private static func requestActivation(processID: pid_t) {
        guard let application = NSRunningApplication(processIdentifier: processID) else { return }
        let isAccepted = application.activate(from: .current) || application.activate(options: [])
        Log.debug("「試してみる」のダイアログを前面に出す要求を送りました（受け付け: \(isAccepted)、openpath がアクティブ: \(NSApp.isActive)）")
    }
}
