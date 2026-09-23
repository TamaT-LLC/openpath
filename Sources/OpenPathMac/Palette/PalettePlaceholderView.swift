import SwiftUI

import OpenPathCore

/// パレットの仮ビュー。検索フィールドのみを持つ。
/// 候補リスト・フッターを含む本実装（#21）に差し替えるまで、ウィンドウの表示確認に使う。
public struct PalettePlaceholderView: View {
    private enum Constants {
        static let placeholder = "フォルダを検索"
        static let searchIconName = "magnifyingglass"
        static let horizontalPadding: CGFloat = 12
        static let iconSpacing: CGFloat = 8
    }

    private let metrics: PaletteMetrics
    @State private var query = ""
    @FocusState private var isSearchFieldFocused: Bool

    public init(metrics: PaletteMetrics = .standard) {
        self.metrics = metrics
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Constants.iconSpacing) {
                Image(systemName: Constants.searchIconName)
                    .foregroundStyle(.secondary)
                TextField(Constants.placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isSearchFieldFocused)
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .frame(height: metrics.searchFieldHeight)
            Divider()
            Spacer(minLength: 0)
        }
        .onAppear { isSearchFieldFocused = true }
    }
}
