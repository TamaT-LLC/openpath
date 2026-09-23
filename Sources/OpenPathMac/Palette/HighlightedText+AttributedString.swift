import SwiftUI

import OpenPathCore

extension HighlightedText {
    /// マッチ位置をアクセントカラーの太字にした表示用の文字列（UX-001 §3）。
    /// 太字は字体ではなく強調の意図として付け、Text 側のフォント（サイズ）をそのまま生かす。
    func attributedString() -> AttributedString {
        segments.reduce(into: AttributedString()) { result, segment in
            var part = AttributedString(segment.text)
            if segment.isHighlighted {
                part.swiftUI.foregroundColor = .accentColor
                part.inlinePresentationIntent = .stronglyEmphasized
            }
            result.append(part)
        }
    }
}
