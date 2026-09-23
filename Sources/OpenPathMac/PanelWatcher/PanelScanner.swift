import ApplicationServices

import OpenPathCore

/// ウィンドウが NSOpenPanel かどうかを判定し、該当すれば PanelContext を返す（判定は #18 で実装する）。
///
/// - 観測中のアプリの `kAXWindowsAttribute` の各ウィンドウに対して、axQueue 上で同期的に呼ばれる。
/// - サンドボックスアプリや `beginSheetModal` のパネルはウィンドウの子要素（AXSheet）として現れるため、
///   シートの確認は判定関数の側で行う。
/// - 同じパネルには同じ `PanelContext.ID` を返すこと。id が変わると別のパネルとみなし、`panelGone` → `panelAppeared` を送る。
public typealias PanelDetector = @Sendable (AXUIElement) -> PanelContext?

/// 観測中のアプリのウィンドウを列挙してパネルを探す。AX のプロセス間呼び出しを伴うため axQueue で呼ぶこと。
enum PanelScanner {
    static func scan(processID: pid_t, detectPanel: PanelDetector) -> PanelScanOutcome {
        let application = AXUIElementCreateApplication(processID)
        let windowsValue: CFTypeRef
        do {
            windowsValue = try application.copyAttributeValue(kAXWindowsAttribute)
        } catch let error as AXElementError {
            // パネルがないと言い切れるエラーかどうかの判断は OpenPathCore の PanelScanOutcome で行う
            return PanelScanOutcome(windowListError: WindowListError(error.code))
        } catch {
            return .unavailable
        }
        guard let windows = AXAttributeCast.cast(windowsValue, to: [AXUIElement].self) else {
            return .unavailable
        }
        return .found(windows.compactMap(detectPanel))
    }
}

extension WindowListError {
    /// `AXError` を Core の語彙に写す。扱いを分けない AXError はまとめて `.other` にする。
    init(_ code: AXError) {
        switch code {
        case .noValue:
            self = .noValue
        case .invalidUIElement:
            self = .invalidElement
        case .attributeUnsupported:
            self = .attributeUnsupported
        case .cannotComplete:
            self = .cannotComplete
        default:
            self = .other
        }
    }
}
