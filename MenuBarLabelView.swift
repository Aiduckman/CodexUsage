import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: viewModel.menuBarLevel.symbolName)
            Text(viewModel.menuBarLabel)
                .monospacedDigit()
        }
        .foregroundColor(viewModel.menuBarLevel.color)
    }
}
