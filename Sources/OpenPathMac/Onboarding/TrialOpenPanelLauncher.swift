import AppKit

import OpenPathCore

/// 「試してみる」で「開く」ダイアログを出す（UX-001 §7）。方式の理由は OpenPathCore の `TrialOpenPanelScript` を参照。
///
/// osascript は他のプロセスから起動されると自分では前面に出ないため、アプリとして登録されるのを待って前面に出す。
/// PanelWatcher は最前面のアプリだけを観測するので、前面に出ればパネルを検知してパレットが重なる。
/// 前面に出せなかった場合も、利用者がダイアログをクリックすれば同じように検知される。
@MainActor
final class TrialOpenPanelLauncher {
    private enum Constants {
        /// osascript がアプリとして登録されたかを確かめる間隔
        static let activationPollInterval: Duration = .milliseconds(100)
        /// 登録を待つ上限。ダイアログは通常 1 秒以内に出る
        static let activationTimeout: Duration = .seconds(3)
    }

    private var process: Process?
    private var activationTask: Task<Void, Never>?

    /// ダイアログを出す。前回のダイアログがまだ開いていれば、重ねて出さずに前面に出し直す。
    func launch() {
        if let process, process.isRunning {
            activateWhenRegistered(processID: process.processIdentifier)
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
        activateWhenRegistered(processID: process.processIdentifier)
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

    private func activateWhenRegistered(processID: pid_t) {
        activationTask?.cancel()
        activationTask = Task { @MainActor in
            let deadline = ContinuousClock.now.advanced(by: Constants.activationTimeout)
            while !Task.isCancelled, ContinuousClock.now < deadline {
                if let application = NSRunningApplication(processIdentifier: processID) {
                    // 「試してみる」を押した直後で openpath がアクティブなうちに、前面を osascript へ譲る
                    if !application.activate(from: .current) {
                        Log.info("「試してみる」のダイアログを前面に出せませんでした")
                    }
                    return
                }
                try? await Task.sleep(for: Constants.activationPollInterval)
            }
            guard !Task.isCancelled else { return }
            Log.info("「試してみる」のダイアログがアプリとして登録されませんでした")
        }
    }
}
