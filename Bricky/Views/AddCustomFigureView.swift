import SwiftUI
import PhotosUI

/// Form for adding a custom minifigure to the local catalog.
/// The user supplies a photo (from camera or library) and metadata
/// (name, theme, year, set). The figure is saved via
/// `MinifigureCatalog.addUserFigure` and its photo via
/// `UserFigureImageStorage`, making it immediately available to
/// the identification pipeline and search.
struct AddCustomFigureView: View {
    /// Optional pre-populated photo (e.g. passed from the correction
    /// picker when the user taps "None of these — add to catalog").
    let initialImage: UIImage?
    let onSaved: (Minifigure) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var theme: String = ""
    @State private var year: String = String(Calendar.current.component(.year, from: Date()))
    @State private var setNumber: String = ""
    @State private var descriptionText: String = ""
    @State private var chosenImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var errorMessage: String?

    init(initialImage: UIImage? = nil, onSaved: @escaping (Minifigure) -> Void = { _ in }) {
        self.initialImage = initialImage
        self.onSaved = onSaved
        _chosenImage = State(initialValue: initialImage)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    photoSection
                }

                Section("Details") {
                    TextField("Name (required)", text: $name)
                        .autocorrectionDisabled()

                    themePicker

                    TextField("Year", text: $year)
                        .keyboardType(.numberPad)

                    TextField("Set number (optional)", text: $setNumber)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)

                    ZStack(alignment: .topLeading) {
                        if descriptionText.isEmpty {
                            Text("Description / notes (optional)")
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 8)
                        }
                        TextEditor(text: $descriptionText)
                            .frame(minHeight: 80)
                            .scrollContentBackground(.hidden)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Text("Custom figures are saved on this device only and become searchable in the catalog immediately. They'll also be used to help identify future scans.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Custom Figure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(.body.weight(.semibold))
                        .disabled(!canSave)
                }
            }
            .photosPicker(isPresented: $showPhotoPicker,
                          selection: $photoPickerItem,
                          matching: .images)
            .onChange(of: photoPickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run { chosenImage = img }
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                CustomFigureCameraPicker { image in
                    chosenImage = image
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var photoSection: some View {
        if let img = chosenImage {
            VStack(spacing: 10) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 12) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Retake", systemImage: "camera")
                    }
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Choose", systemImage: "photo.on.rectangle")
                    }
                    Button(role: .destructive) {
                        chosenImage = nil
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        } else {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 120)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text("No photo yet").font(.caption).foregroundStyle(.secondary)
                        }
                    }

                HStack(spacing: 12) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var themePicker: some View {
        let catalogThemes = MinifigureCatalog.shared.themes
        HStack {
            TextField("Theme (required)", text: $theme)
                .autocorrectionDisabled()
            if !catalogThemes.isEmpty {
                Menu {
                    ForEach(catalogThemes, id: \.self) { t in
                        Button(t) { theme = t }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    // MARK: - Logic

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !theme.trimmingCharacters(in: .whitespaces).isEmpty &&
        chosenImage != nil
    }

    private func save() {
        guard canSave, let image = chosenImage else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedTheme = theme.trimmingCharacters(in: .whitespaces)
        let parsedYear = Int(year.trimmingCharacters(in: .whitespaces)) ?? 0

        let id = MinifigureCatalog.newUserFigureId()
        guard let imageURL = UserFigureImageStorage.shared.save(image, for: id) else {
            errorMessage = "Couldn't save the photo. Please try another image."
            return
        }

        // Compose a descriptive name that includes set/description hints
        // so the catalog search surfaces it for related queries.
        var fullName = trimmedName
        let setTrimmed = setNumber.trimmingCharacters(in: .whitespaces)
        if !setTrimmed.isEmpty {
            fullName += " (Set \(setTrimmed))"
        }
        let descTrimmed = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !descTrimmed.isEmpty {
            fullName += " — \(descTrimmed)"
        }

        let figure = Minifigure(
            id: id,
            name: fullName,
            theme: trimmedTheme,
            year: parsedYear,
            partCount: 0,
            imgURL: imageURL.absoluteString,
            parts: []
        )

        MinifigureCatalog.shared.addUserFigure(figure)
        onSaved(figure)
        dismiss()
    }
}

// MARK: - Camera picker wrapper

/// Minimal UIImagePickerController wrapper for capturing a photo.
/// Used instead of AVFoundation so the add-figure flow stays simple.
private struct CustomFigureCameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            if let image = (info[.originalImage] as? UIImage)?.normalizedOrientation() {
                onImage(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

#Preview {
    AddCustomFigureView()
}
