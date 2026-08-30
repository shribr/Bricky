import SwiftUI

/// Minimal browser for bundled LDraw set models. Each opens in the shared 3D
/// step-by-step viewer (rendering real part meshes).
struct SetModelsView: View {
    private let entries = SetModelLibrary.entries()
    @State private var selected: SetModelEntry?

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Set Models Yet",
                    systemImage: "cube.transparent",
                    description: Text("Bundled LDraw set models will appear here.")
                )
            } else {
                List(entries) { entry in
                    Button {
                        selected = entry
                        HapticManager.selection()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "cube.transparent")
                                .font(.title3)
                                .foregroundStyle(Color.legoBlue)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if let number = entry.setNumber {
                                    Text("Set \(number)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Open interactive 3D instructions")
                }
            }
        }
        .navigationTitle("Set Models")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selected) { entry in
            if let text = SetModelLibrary.modelText(for: entry) {
                BuildStepViewer(setModelText: text, title: entry.name)
            }
        }
    }
}

#Preview {
    NavigationStack { SetModelsView() }
}
