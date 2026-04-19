import SwiftUI

/// Sprint 5 / F2 — Edit free-form tags for a saved scan session.
struct ScanTagEditorView: View {
    let sessionID: UUID
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var history = ScanHistoryStore.shared

    @State private var tags: [String] = []
    @State private var newTag: String = ""
    @FocusState private var newTagFocused: Bool

    /// Suggested tags from other scans the user has tagged.
    private var suggestions: [String] {
        history.allTags.filter { tag in
            !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame })
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Current Tags") {
                    if tags.isEmpty {
                        Text("No tags yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(tags, id: \.self) { tag in
                            HStack {
                                Image(systemName: "tag.fill")
                                    .foregroundStyle(Color.legoBlue)
                                Text(tag)
                                Spacer()
                                Button {
                                    tags.removeAll { $0 == tag }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("Add Tag") {
                    HStack {
                        TextField("e.g. Friend's house, Yard sale", text: $newTag)
                            .focused($newTagFocused)
                            .onSubmit { addNewTag() }
                        Button("Add", action: addNewTag)
                            .disabled(trimmed.isEmpty)
                    }
                }

                if !suggestions.isEmpty {
                    Section("From Other Scans") {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                tags.append(suggestion)
                            } label: {
                                HStack {
                                    Image(systemName: "tag")
                                    Text(suggestion)
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(Color.legoGreen)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { loadInitialTags() }
        }
    }

    private var trimmed: String {
        newTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addNewTag() {
        let candidate = trimmed
        guard !candidate.isEmpty else { return }
        if !tags.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
            tags.append(candidate)
        }
        newTag = ""
        newTagFocused = true
    }

    private func loadInitialTags() {
        if let entry = history.entries.first(where: { $0.id == sessionID }) {
            tags = entry.tags
        }
    }

    private func save() {
        history.updateTags(sessionID: sessionID, tags: tags)
        dismiss()
    }
}
