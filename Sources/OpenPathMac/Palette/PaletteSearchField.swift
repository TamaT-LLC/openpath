import SwiftUI

/// パレット上部の検索フィールド（UX-001 §3）。
/// 入力欄は IME の変換中を判定するため NSTextField（`PaletteSearchTextField`）で実装し、
/// パレットがキーウィンドウになるたびにフォーカスする。キー操作は `PaletteKeyController` が処理する。
struct PaletteSearchField: View {
    private enum Constants {
        static let placeholder = "フォルダを検索"
        static let searchIconName = "magnifyingglass"
        static let horizontalPadding: CGFloat = 12
        static let iconSpacing: CGFloat = 8
    }

    @Binding var query: String

    var body: some View {
        HStack(spacing: Constants.iconSpacing) {
            Image(systemName: Constants.searchIconName)
                .foregroundStyle(.secondary)
            PaletteSearchTextField(text: $query, placeholder: Constants.placeholder)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) { Divider() }
    }
}
