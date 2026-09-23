import SwiftUI

import OpenPathCore

/// 候補リスト。行数が最大表示行数を超える分はスクロールさせ、選択行が見えるように追従する。
/// 候補が 0 件のときは、PaletteMetrics が確保している 1 行分に案内を出す（UX-001 §5）。
struct PaletteCandidateList: View {
    let viewModel: PaletteViewModel
    let rowHeight: CGFloat

    var body: some View {
        if let emptyMessage = viewModel.emptyMessage {
            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, PaletteRowLayout.nameColumnLeading)
                .padding(.trailing, PaletteRowLayout.horizontalPadding)
                .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
        } else {
            // 「3分前」などの相対日時を、パレットを出したままでも分単位で更新する。
            // context.date は直前の分の境界（現在より前）で相対日時が 1 単位ずれ得るため、描画時の現在時刻を使う
            TimelineView(.everyMinute) { _ in
                rowList(now: Date())
            }
        }
    }

    private func rowList(now: Date) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                        PaletteRowView(
                            presentation: PaletteRowPresentation(row: row, homeDirectory: viewModel.homeDirectory),
                            lastUsedText: RelativeDateFormatter.string(from: row.lastUsed, relativeTo: now),
                            isSelected: index == viewModel.selectedIndex
                        )
                        .frame(height: rowHeight)
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.select(at: index) }
                        .id(row.id)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: viewModel.selectedRow?.id) { _, selectedID in
                guard let selectedID else { return }
                // anchor を指定しないと、選択行が見える最小限だけスクロールする
                proxy.scrollTo(selectedID)
            }
        }
    }
}
