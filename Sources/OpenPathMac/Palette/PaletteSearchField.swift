import SwiftUI

/// パレット上部の検索フィールド（UX-001 §3）。表示されたら入力を受け付けられるようフォーカスする。
/// キー操作（↑↓・Enter・Esc・Tab・IME）の扱いはキー処理（#22）の責務で、ここでは文字入力のみを扱う。
struct PaletteSearchField: View {
    private enum Constants {
        static let placeholder = "フォルダを検索"
        static let searchIconName = "magnifyingglass"
        static let horizontalPadding: CGFloat = 12
        static let iconSpacing: CGFloat = 8
    }

    @Binding var query: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Constants.iconSpacing) {
            Image(systemName: Constants.searchIconName)
                .foregroundStyle(.secondary)
            TextField(Constants.placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                // パスやディレクトリ名の入力なので自動修正は邪魔になる
                .autocorrectionDisabled()
                .focused($isFocused)
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) { Divider() }
        .onAppear { isFocused = true }
    }
}
