import SwiftUI

import OpenPathCore

/// 候補行の列の寸法。0 件の案内も表示名の列に揃えるため、行と共有する。
enum PaletteRowLayout {
    static let horizontalPadding: CGFloat = 10
    static let columnSpacing: CGFloat = 10
    static let iconWidth: CGFloat = 16
    /// アイコンを広げた分だけ表示名の列を縮め、場所の列の開始位置を保つ（UX-001 §3）。
    static let nameColumnWidth: CGFloat = 174
    /// 「12か月前」が収まる幅
    static let lastUsedColumnWidth: CGFloat = 64

    /// 表示名の列の開始位置。0 件の案内の字下げに使う
    static var nameColumnLeading: CGFloat {
        horizontalPadding + iconWidth + columnSpacing
    }
}

/// 候補 1 行: 種類のアイコン / 表示名 / 場所（親ディレクトリ）/ 最終使用日時（UX-001 §3）。
struct PaletteRowView: View {
    private enum Constants {
        static let selectionInset: CGFloat = 4
        static let selectionCornerRadius: CGFloat = 6
    }

    private var iconName: String {
        if presentation.isDirectory {
            return isSelected ? "folder.fill" : "folder"
        }
        return isSelected ? "doc.fill" : "doc"
    }

    let presentation: PaletteRowPresentation
    let lastUsedText: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: PaletteRowLayout.columnSpacing) {
            Image(systemName: iconName)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: PaletteRowLayout.iconWidth)
                .accessibilityHidden(true)
            Text(presentation.name.attributedString())
                .lineLimit(1)
                .frame(width: PaletteRowLayout.nameColumnWidth, alignment: .leading)
            PaletteLocationText(variants: presentation.locationVariants)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(lastUsedText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: PaletteRowLayout.lastUsedColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, PaletteRowLayout.horizontalPadding)
        .frame(maxHeight: .infinity)
        // VoiceOver では列ごとではなく 1 候補を 1 要素として読ませる
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .background {
            if isSelected {
                // 選択色にアクセントカラーを使うとハイライト（アクセントカラー）が埋もれるため、非強調の選択色にする
                RoundedRectangle(cornerRadius: Constants.selectionCornerRadius)
                    .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
                    .padding(.horizontal, Constants.selectionInset)
            }
        }
    }
}

/// 場所の列。中央省略の候補から列幅に収まる最初のものを表示し、1 行に収める。
/// どれも収まらない場合は最も省略した候補を文字単位で中央省略する。
private struct PaletteLocationText: View {
    let variants: [HighlightedText]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(variants.indices, id: \.self) { index in
                Text(variants[index].attributedString())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}
