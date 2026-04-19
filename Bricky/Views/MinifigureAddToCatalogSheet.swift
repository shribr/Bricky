import SwiftUI
import UIKit

/// Sheet that lets the user save a model-suggested minifigure that isn't in
/// the local catalog. Pre-populates name from the AI candidate; user picks
/// theme + year, then we persist as a `userFigure` and (optionally) mark it
/// scanned + add to the inventory.
struct MinifigureAddToCatalogSheet: View {
    let candidate: MinifigureIdentificationService.ResolvedCandidate
    let capturedImage: UIImage?
    /// Called once the figure has been saved to the catalog. Receives the
    /// newly created `Minifigure`.
    let onSaved: (Minifigure) -> Void

    @StateObject private var catalog = MinifigureCatalog.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var theme: String
    @State private var yearString: String
    @State private var addToCollection: Bool = true

    init(candidate: MinifigureIdentificationService.ResolvedCandidate,
         capturedImage: UIImage?,
         onSaved: @escaping (Minifigure) -> Void) {
        self.candidate = candidate
        self.capturedImage = capturedImage
        self.onSaved = onSaved
        _name = State(initialValue: candidate.modelName)
        _theme = State(initialValue: "Custom")
        _yearString = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let img = capturedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    } else {
                        Image(systemName: "person.crop.square.filled.and.at.rectangle")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }

                Section("Details") {
                    TextField("Name", text: $name, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Theme", text: $theme)
                    TextField("Year (optional)", text: $yearString)
                        .keyboardType(.numberPad)
                }

                if !candidate.reasoning.isEmpty {
                    Section("AI suggestion") {
                        Text(candidate.reasoning)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Add to my collection", isOn: $addToCollection)
                } footer: {
                    Text("The captured photo will be used as this figure's image. You can edit details later from the catalog.")
                        .font(.caption)
                }
            }
            .navigationTitle("Add to Catalog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTheme = theme.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = Int(yearString.trimmingCharacters(in: .whitespaces)) ?? 0

        let savedImageURL = persistCapturedImageIfNeeded()

        let figure = Minifigure(
            id: MinifigureCatalog.newUserFigureId(),
            name: trimmedName.isEmpty ? "Untitled minifigure" : trimmedName,
            theme: trimmedTheme.isEmpty ? "Custom" : trimmedTheme,
            year: year,
            partCount: 0,
            imgURL: savedImageURL?.absoluteString,
            parts: []
        )

        let stored = catalog.addUserFigure(figure)

        if addToCollection {
            MinifigureCollectionStore.shared.markScanned(stored.id)
        }

        onSaved(stored)
        dismiss()
    }

    /// Save the captured photo to Documents/UserMinifigureImages/ so the
    /// figure has a stable image url for the catalog tile + detail view.
    private func persistCapturedImageIfNeeded() -> URL? {
        guard let image = capturedImage,
              let data = image.jpegData(compressionQuality: 0.85) else {
            return nil
        }
        let fm = FileManager.default
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UserMinifigureImages", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let filename = "\(UUID().uuidString).jpg"
        let url = dir.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
