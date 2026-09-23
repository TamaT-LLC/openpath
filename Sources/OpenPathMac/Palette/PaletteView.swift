import SwiftUI

import OpenPathCore

/// パレットの本体ビュー（UX-001 §3）。検索フィールド・候補リスト・フッターを縦に並べる。
///
/// 検索フィールドとフッターの高さは PaletteMetrics に合わせ、候補リストは残りを埋める。
/// ウィンドウの高さ（PaletteWindow.rowCount）が候補数に追従していれば、リストはちょうど表示行数分になる。
/// 色はシステムカラー（secondary / accentColor / red 等）のみを使い、ライト / ダークの両方に追従する。
public struct PaletteView: View {
    @Bindable private var viewModel: PaletteViewModel
    private let metrics: PaletteMetrics

    public init(viewModel: PaletteViewModel, metrics: PaletteMetrics = .standard) {
        self.viewModel = viewModel
        self.metrics = metrics
    }

    public var body: some View {
        VStack(spacing: 0) {
            PaletteSearchField(query: $viewModel.query)
                .frame(height: metrics.searchFieldHeight)
            PaletteCandidateList(viewModel: viewModel, rowHeight: metrics.rowHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            PaletteFooterView(content: viewModel.footer)
                .frame(height: metrics.footerHeight)
        }
    }
}

extension PaletteWindow where Content == PaletteView {
    /// パレットの本体ビューで生成する。ビューとウィンドウで同じ寸法を使う。
    public convenience init(viewModel: PaletteViewModel, metrics: PaletteMetrics = .standard) {
        self.init(rootView: PaletteView(viewModel: viewModel, metrics: metrics), metrics: metrics)
    }
}
