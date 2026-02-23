import SwiftUI

/// Horizontal segmented bar showing proportional values
struct SegmentedBar: View {
    struct Segment: Identifiable {
        let id = UUID()
        let value: Double
        let color: Color
        let label: String
    }

    let segments: [Segment]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(segment.color)
                        .frame(width: max(geometry.size.width * segment.value, 1))
                        .help(segment.label)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
