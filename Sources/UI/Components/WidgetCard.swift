import SwiftUI

/// Reusable card container for dashboard widgets
struct WidgetCard<Content: View>: View {
    let title: String
    let symbol: String
    let content: () -> Content

    init(title: String, symbol: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            content()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
