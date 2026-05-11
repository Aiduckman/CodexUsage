import SwiftUI

struct OpenAIMarkView: View {
    var color: Color

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                Capsule(style: .continuous)
                    .stroke(color, lineWidth: 1.7)
                    .frame(width: 10, height: 5.5)
                    .offset(x: 4.6)
                    .rotationEffect(.degrees(Double(index) * 60))
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}
