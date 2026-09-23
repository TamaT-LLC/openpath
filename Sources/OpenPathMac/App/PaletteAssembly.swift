import OpenPathCore

/// パレットを構成する部品（ビューモデル・ウィンドウ・キー操作・表示の振り分け）をまとめて生成し、保持する。
///
/// AppCoordinator へは `presenter`（PaletteDisplaying）を渡し、確定・Esc は `onEvent` で受け取る。
/// PaletteKeyController はキーの監視を解放で止めるため、アプリの寿命の間ここで保持し続ける。
@MainActor
final class PaletteAssembly {
    let presenter: PalettePresenter
    private let window: PaletteWindow<PaletteView>
    private let keyController: PaletteKeyController

    /// パレットで確定・Esc が押されたときに呼ばれる。`PaletteEvent.coordinatorEvent` で AppCoordinator へ渡す。
    var onEvent: ((PaletteEvent) -> Void)? {
        get { keyController.onEvent }
        set { keyController.onEvent = newValue }
    }

    /// - Parameters:
    ///   - index: 候補の検索先。クエリと、検索語に打ったパスの存在確認は MainActor の外で走る。
    ///   - includeFiles: 設定 include_files。候補を引くたびに読む。
    init(index: CandidateIndex, includeFiles: @escaping @MainActor @Sendable () -> Bool) {
        let viewModel = PaletteViewModel()
        let window = PaletteWindow(viewModel: viewModel)
        self.window = window
        presenter = PalettePresenter(
            viewModel: viewModel,
            window: window,
            includeFiles: includeFiles,
            search: PaletteCandidateSearch.make(index: index)
        )
        keyController = PaletteKeyController(window: window.window, viewModel: viewModel)
    }
}
