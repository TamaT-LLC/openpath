import Dispatch

import OpenPathCore

private enum AXQueueConstants {
    static let label = "\(AppInfo.bundleIdentifier).ax"
}

/// AX 呼び出し専用のシリアルキュー（DSN-001 §5）。
///
/// サンドボックスアプリのパネルは要素アクセスのプロセス間往復が遅く、メインスレッドで呼ぶと UI が止まるためここで呼ぶ。
/// シリアルにしているのは、同じアプリへの問い合わせを並行させても AX 側で直列化されて速くならず、
/// 呼び出し回数の上限（1 パネルあたり 50 回）の管理も難しくなるため。
public let axQueue = DispatchQueue(label: AXQueueConstants.label, qos: .userInteractive)

/// `work` を `axQueue` で実行し、結果を MainActor で受け取る。
@MainActor
public func onAXQueue<T>(_ work: @escaping () -> T) async -> T {
    await withCheckedContinuation { continuation in
        axQueue.async {
            continuation.resume(returning: work())
        }
    }
}

/// `work` を `axQueue` で実行し、結果または投げたエラーを MainActor で受け取る。
@MainActor
public func onAXQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        axQueue.async {
            continuation.resume(with: Result(catching: work))
        }
    }
}
