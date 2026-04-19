import PhotosUI
import SwiftUI

/// View for sharing a build creation to the community
struct ShareCreationView: View {
    @ObservedObject private var communityService = CloudKitCommunityService.shared
    @ObservedObject private var auth = AuthenticationService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var projectName: String = ""
    @State private var caption: String = ""
    @State private var selectedCategory: ProjectCategory = .decoration
    @State private var selectedDifficulty: Difficulty = .medium
    @State private var selectedImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isPosting = false
    @State private var postError: String?

    var body: some View {
        Form {
            // Photo section
            Section {
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(Color.legoBlue)
                                Text("Add a Photo")
                                    .font(.headline)
                                Text("Show off your completed build")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 40)
                            Spacer()
                        }
                    }
                }
                .onChange(of: photoPickerItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            selectedImage = uiImage
                        }
                    }
                }
            } header: {
                Text("Photo")
            }

            // Build details
            Section {
                TextField("Build Name", text: $projectName)

                Picker("Category", selection: $selectedCategory) {
                    ForEach(ProjectCategory.allCases, id: \.self) { category in
                        Label(category.rawValue.capitalized, systemImage: category.systemImage)
                            .tag(category)
                    }
                }

                Picker("Difficulty", selection: $selectedDifficulty) {
                    ForEach(Difficulty.allCases, id: \.self) { diff in
                        Text(diff.rawValue.capitalized).tag(diff)
                    }
                }
            } header: {
                Text("Build Details")
            }

            // Caption
            Section {
                TextField("Tell others about your build...", text: $caption, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("Caption")
            }

            // Post button
            Section {
                Button {
                    Task { await postBuild() }
                } label: {
                    HStack {
                        Spacer()
                        if isPosting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Label("Share with Community", systemImage: "paperplane.fill")
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .disabled(projectName.trimmingCharacters(in: .whitespaces).isEmpty || isPosting)
                .listRowBackground(
                    projectName.trimmingCharacters(in: .whitespaces).isEmpty
                        ? Color.gray.opacity(0.3)
                        : Color.legoBlue
                )
                .foregroundStyle(.white)

                if let error = postError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Share Build")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    // MARK: - Post Build

    private func postBuild() async {
        guard let userId = auth.userIdentifier else { return }
        isPosting = true
        postError = nil

        var imageData: Data?
        if let image = selectedImage {
            imageData = image.jpegData(compressionQuality: 0.7)
        }

        let post = CommunityPost(
            authorId: userId,
            authorName: communityService.userProfile?.username ?? auth.displayName ?? "Builder",
            authorAvatar: communityService.userProfile?.avatarSystemName ?? "person.crop.circle.fill",
            projectName: projectName.trimmingCharacters(in: .whitespaces),
            projectCategory: selectedCategory.rawValue,
            projectDifficulty: selectedDifficulty.rawValue,
            caption: caption.trimmingCharacters(in: .whitespaces),
            imageData: imageData
        )

        do {
            try await communityService.createPost(post)
            await MainActor.run {
                isPosting = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                postError = error.localizedDescription
                isPosting = false
            }
        }
    }
}

/// Pre-filled share creation from an existing build suggestion
struct ShareBuildSuggestionView: View {
    let suggestion: BuildSuggestionEngine.BuildSuggestion
    @ObservedObject private var communityService = CloudKitCommunityService.shared
    @ObservedObject private var auth = AuthenticationService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var caption: String = ""
    @State private var selectedImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isPosting = false
    @State private var postError: String?

    var body: some View {
        Form {
            // Build info (pre-filled, read-only)
            Section {
                HStack {
                    Image(systemName: suggestion.project.imageSystemName)
                        .font(.title)
                        .foregroundStyle(Color.legoBlue)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.project.name)
                            .font(.headline)
                        Text(suggestion.project.category.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Build")
            }

            // Photo
            Section {
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(Color.legoBlue)
                                Text("Add a Photo of Your Build")
                                    .font(.headline)
                            }
                            .padding(.vertical, 40)
                            Spacer()
                        }
                    }
                }
                .onChange(of: photoPickerItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            selectedImage = uiImage
                        }
                    }
                }
            } header: {
                Text("Photo")
            }

            // Caption
            Section {
                TextField("Tell others about your build...", text: $caption, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("Caption")
            }

            // Post
            Section {
                Button {
                    Task { await postBuild() }
                } label: {
                    HStack {
                        Spacer()
                        if isPosting {
                            ProgressView().tint(.white)
                        } else {
                            Label("Share with Community", systemImage: "paperplane.fill")
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .disabled(isPosting)
                .listRowBackground(Color.legoBlue)
                .foregroundStyle(.white)

                if let error = postError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Share to Community")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func postBuild() async {
        guard let userId = auth.userIdentifier else { return }
        isPosting = true
        postError = nil

        var imageData: Data?
        if let image = selectedImage {
            imageData = image.jpegData(compressionQuality: 0.7)
        }

        let post = CommunityPost(
            authorId: userId,
            authorName: communityService.userProfile?.username ?? auth.displayName ?? "Builder",
            authorAvatar: communityService.userProfile?.avatarSystemName ?? "person.crop.circle.fill",
            projectName: suggestion.project.name,
            projectCategory: suggestion.project.category.rawValue,
            projectDifficulty: suggestion.project.difficulty.rawValue,
            caption: caption.trimmingCharacters(in: .whitespaces),
            imageData: imageData
        )

        do {
            try await communityService.createPost(post)
            await MainActor.run {
                isPosting = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                postError = error.localizedDescription
                isPosting = false
            }
        }
    }
}
