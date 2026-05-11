import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        HStack(spacing: 3) {
            OpenAIMarkView(color: Color(red: 0.06, green: 0.64, blue: 0.50))
            Text(viewModel.menuBarLabel)
                .monospacedDigit()
                .foregroundColor(viewModel.menuBarNumberColor)
        }
    }
}
