import ApplicationServices
import Foundation
import OpenPathCore

/// 保存パネルの標準リスト表示を AX キューで読み、根拠を持つ現在地だけを返す。
/// collapsed・空一覧・検索中・未対応レイアウトを、表示名から推測して成功にしない。
@MainActor
enum SavePanelLocationReader {
    /// 記録済みパネルの現在地を期限内で読む。特定不能は nil、AX の失敗と期限切れは呼び出し側へ伝える。
    static func path(in window: AXUIElement?, cutoff: ScanCutoff) async throws -> String? {
        guard let window else { return nil }
        return try await onAXQueue {
            let reader = AXPanelTreeReader()
            let window = AXPanelTreeReader.limitingMessagingTimeout(window)
            return try SavePanelLocationSearch.path(
                in: window, reader: reader, cutoff: cutoff,
                boundedChildren: children,
                value: { try attribute(kAXValueAttribute, of: $0, as: String.self) },
                disclosureLevel: { try attribute(kAXDisclosureLevelAttribute, of: $0, as: Int.self) },
                disclosedByRow: {
                    let ancestor: AXUIElement? = try attribute(kAXDisclosedByRowAttribute, of: $0, as: AXUIElement.self)
                    return ancestor.map(AXPanelTreeReader.limitingMessagingTimeout)
                },
                itemPath: { node in
                    guard let url = try reader.url(of: node), url.isFileURL,
                          let fileURL = (url as NSURL).filePathURL, fileURL.isFileURL else { return nil }
                    // filePathURL は file-reference のみ実パスへ変換する。通常 URL の symlink は辿らない。
                    let path = fileURL.path
                    guard !path.hasPrefix("/.file/id=") else { return nil }
                    return path
                }
            )
        }
    }

    /// AXChildren の件数 API を持たない標準コンテナもあるため、上限 + 1 個を直接読み、全件取得を確認する。
    /// 配列の読み取り失敗を空と推測せず、検証不能として扱う。
    nonisolated private static func children(of node: AXUIElement, limit: Int) throws -> [AXUIElement]? {
        var values: CFArray?
        let result = AXUIElementCopyAttributeValues(node, kAXChildrenAttribute as CFString, 0, limit + 1, &values)
        switch result {
        case .success:
            guard let values, let children = AXAttributeCast.cast(values, to: [AXUIElement].self), children.count <= limit else { return nil }
            return children.map(AXPanelTreeReader.limitingMessagingTimeout)
        case .noValue, .attributeUnsupported:
            return []
        case .invalidUIElement:
            throw PanelTreeReadError.elementGone
        default:
            throw PanelTreeReadError.unavailable
        }
    }

    /// 未対応・値なしだけを nil とし、要素の消失や通信失敗は検証不能として呼び出し側へ伝える。
    nonisolated private static func attribute<T>(_ name: String, of node: AXUIElement, as type: T.Type) throws -> T? {
        do {
            return AXAttributeCast.cast(try node.copyAttributeValue(name), to: type)
        } catch let error as AXElementError {
            switch error.code {
            case .attributeUnsupported, .noValue: return nil
            case .invalidUIElement: throw PanelTreeReadError.elementGone
            default: throw PanelTreeReadError.unavailable
            }
        }
    }
}
