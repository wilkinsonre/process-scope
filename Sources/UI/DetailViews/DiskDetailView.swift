import SwiftUI

struct DiskDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Volumes") {
                    let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/")
                    let total = attrs?[.systemSize] as? UInt64 ?? 0
                    let free = attrs?[.systemFreeSize] as? UInt64 ?? 0
                    let used = total - free

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "internaldrive.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text("Macintosh HD")
                                    .font(.headline)
                                Text("\(ByteCountFormatter.string(fromByteCount: Int64(free), countStyle: .file)) available of \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        SegmentedBar(segments: [
                            .init(value: total > 0 ? Double(used) / Double(total) : 0, color: .orange, label: "Used"),
                            .init(value: total > 0 ? Double(free) / Double(total) : 0, color: .secondary.opacity(0.3), label: "Free"),
                        ])
                        .frame(height: 12)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .navigationTitle("Storage")
    }
}
