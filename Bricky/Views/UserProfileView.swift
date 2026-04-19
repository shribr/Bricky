import SwiftUI

/// User profile view for viewing and editing the current user's profile
struct UserProfileView: View {
    @ObservedObject private var communityService = CloudKitCommunityService.shared
    @ObservedObject private var auth = AuthenticationService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var editUsername: String = ""
    @State private var editBio: String = ""
    @State private var editAvatar: String = "person.crop.circle.fill"
    @State private var isSaving = false
    @State private var userPosts: [CommunityPost] = []
    @State private var isLoadingPosts = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                profileHeader
                statsSection

                if !userPosts.isEmpty {
                    postsSection
                } else if !isLoadingPosts {
                    emptyPostsSection
                }
            }
            .padding()
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                editProfileView
            }
        }
        .task {
            await loadUserPosts()
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            // Avatar
            Image(systemName: communityService.userProfile?.avatarSystemName ?? "person.crop.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.legoBlue)
                .frame(width: 100, height: 100)
                .background(
                    Circle().fill(Color.legoBlue.opacity(0.1))
                )

            // Username
            Text(communityService.userProfile?.username ?? auth.displayName ?? "Builder")
                .font(.title2)
                .fontWeight(.bold)

            // Bio
            if let bio = communityService.userProfile?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Join date
            if let joinDate = communityService.userProfile?.joinDate {
                Text("Joined \(joinDate, style: .date)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Button {
                prepareEdit()
                isEditing = true
            } label: {
                Label("Edit Profile", systemImage: "pencil")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .tint(Color.legoBlue)
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                statItem(value: communityService.userProfile?.buildCount ?? 0, label: "Builds")
                Divider().frame(height: 40)
                statItem(value: communityService.userProfile?.likeCount ?? 0, label: "Likes")
                Divider().frame(height: 40)
                statItem(value: communityService.userProfile?.followerCount ?? 0, label: "Followers")
                Divider().frame(height: 40)
                statItem(value: communityService.userProfile?.followingCount ?? 0, label: "Following")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
            )

            // Streak badge
            StreakBadgeView()
        }
    }

    private func statItem(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Posts Section

    private var postsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Builds")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(userPosts) { post in
                    PostThumbnail(post: post)
                }
            }
        }
    }

    private var emptyPostsSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No builds shared yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Edit Profile

    private var editProfileView: some View {
        Form {
            Section {
                // Avatar picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(ProfileAvatar.allCases) { avatar in
                            Button {
                                editAvatar = avatar.rawValue
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: avatar.rawValue)
                                        .font(.title)
                                        .frame(width: 50, height: 50)
                                        .background(
                                            Circle().fill(
                                                editAvatar == avatar.rawValue
                                                    ? Color.legoBlue.opacity(0.2)
                                                    : Color.gray.opacity(0.1)
                                            )
                                        )
                                        .foregroundStyle(editAvatar == avatar.rawValue ? Color.legoBlue : .secondary)
                                    Text(avatar.label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Avatar")
            }

            Section {
                TextField("Username", text: $editUsername)
                TextField("Bio", text: $editBio, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("Profile Info")
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { isEditing = false }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await saveProfile() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(editUsername.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
    }

    // MARK: - Actions

    private func prepareEdit() {
        editUsername = communityService.userProfile?.username ?? ""
        editBio = communityService.userProfile?.bio ?? ""
        editAvatar = communityService.userProfile?.avatarSystemName ?? "person.crop.circle.fill"
    }

    private func saveProfile() async {
        guard let userId = auth.userIdentifier else { return }
        isSaving = true

        var profile = communityService.userProfile ?? UserProfile(id: userId)
        profile.username = editUsername.trimmingCharacters(in: .whitespaces)
        profile.bio = editBio.trimmingCharacters(in: .whitespaces)
        profile.avatarSystemName = editAvatar

        do {
            try await communityService.saveProfile(profile)
            await MainActor.run {
                isSaving = false
                isEditing = false
            }
        } catch {
            await MainActor.run {
                isSaving = false
            }
        }
    }

    private func loadUserPosts() async {
        guard let userId = auth.userIdentifier else { return }
        isLoadingPosts = true
        userPosts = await communityService.fetchUserPosts(userId: userId)
        isLoadingPosts = false
    }
}

// MARK: - Post Thumbnail

struct PostThumbnail: View {
    let post: CommunityPost

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let imageData = post.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.legoBlue.opacity(0.1)
                    Image(systemName: post.category?.systemImage ?? "cube.fill")
                        .font(.title)
                        .foregroundStyle(Color.legoBlue.opacity(0.5))
                }
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(post.projectName)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)

            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.legoRed)
                Text("\(post.likeCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
