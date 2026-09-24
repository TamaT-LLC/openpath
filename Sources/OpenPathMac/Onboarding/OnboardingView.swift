import SwiftUI

import OpenPathCore

/// 初回起動の案内の 1 ページ（UX-001 §7）。文言とボタンは OpenPathCore の `OnboardingPage` をそのまま並べる。
struct OnboardingView: View {
    private enum Metrics {
        static let width: CGFloat = 460
        static let padding: CGFloat = 24
        static let sectionSpacing: CGFloat = 16
        static let paragraphSpacing: CGFloat = 8
        static let headerSpacing: CGFloat = 12
        static let iconSize: CGFloat = 36
    }

    let page: OnboardingPage
    let onCommand: (OnboardingCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            HStack(spacing: Metrics.headerSpacing) {
                Image(systemName: symbolName)
                    .font(.system(size: Metrics.iconSize))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(page.title)
                    .font(.title2)
                    .bold()
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Metrics.paragraphSpacing) {
                ForEach(Array(page.messageLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button(page.secondaryButton.title) {
                    onCommand(page.secondaryButton.command)
                }
                .keyboardShortcut(.cancelAction)
                Button(page.primaryButton.title) {
                    onCommand(page.primaryButton.command)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Metrics.padding)
        .frame(width: Metrics.width)
    }

    private var symbolName: String {
        switch page {
        case .permissionExplanation: "hand.raised"
        case .awaitingPermission: "gearshape"
        case .ready: "checkmark.circle"
        }
    }
}
