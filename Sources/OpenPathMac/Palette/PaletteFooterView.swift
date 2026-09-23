import SwiftUI

import OpenPathCore

/// パレット下部のフッター。通常はキー操作のヒントを、状態表示があればその文言を出す（UX-001 §3, §5）。
struct PaletteFooterView: View {
    private enum Constants {
        static let horizontalPadding: CGFloat = 12
        static let hintSpacing: CGFloat = 12
        static let keyActionSpacing: CGFloat = 4
    }

    let content: PaletteFooterContent

    var body: some View {
        HStack(spacing: 0) {
            switch content {
            case .keyHints:
                keyHints
            case .status(let message):
                Text(message)
                    .foregroundStyle(.secondary)
                    .help(message)
            case .error(let message):
                Text(message)
                    .foregroundStyle(.red)
                    .help(message)
            }
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .lineLimit(1)
        .padding(.horizontal, Constants.horizontalPadding)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .top) { Divider() }
    }

    private var keyHints: some View {
        HStack(spacing: Constants.hintSpacing) {
            ForEach(PaletteText.keyHints, id: \.key) { hint in
                HStack(spacing: Constants.keyActionSpacing) {
                    Text(hint.key)
                        .fontWeight(.semibold)
                    Text(hint.action)
                }
            }
        }
        .foregroundStyle(.secondary)
    }
}
