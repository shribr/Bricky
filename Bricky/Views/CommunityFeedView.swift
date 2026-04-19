import SwiftUI

/// Community feed showing shared builds from all users
struct CommunityFeedView: View {
    @StateObject private var viewModel = CommunityViewModel()
    @ObservedObject private var communityService = CloudKitCommunityService.shared
    @ObservedObject private var auth = AuthenticationService.shared
    @State private var showShareCreation = false
    @State private var showProfile = false
    @State private var selectedPost: CommunityPost?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        Group {
            if auth.isSignedIn {
                signedInContent
            } else {
                signInPrompt
            }
        }
        .navigationTitle("Community")
        .toolbar {
            if auth.isSignedIn {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showProfile = true
                    } label: {
                        Image(systemName: communityService.userProfile?.avatarSystemName ?? "person.crop.circle")
                    }
                    .accessibilityLabel("View profile")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showShareCreation = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .foregroundStyle(Color.legoBlue)
                    .accessibilityLabel("Share a build")
                }
            }
        }
        .sheet(isPresented: $showShareCreation) {
            NavigationStack {
                ShareCreationView()
            }
        }
        .sheet(isPresented: $showProfile) {
            NavigationStack {
                UserProfileView()
            }
        }
        .sheet(item: $selectedPost) { post in
            NavigationStack {
                CommunityPostDetailView(post: post)
            }
        }
    }

    // MARK: - Signed In Content

    private var signedInContent: some View {
        VStack(spacing: 0) {
            // First-use tip
            FeatureTipView(
                tip: .firstCommunityVisit,
                icon: "person.3.fill",
                title: "Welcome to the Community",
                message: "Share your builds, like and comment on others' creations, and follow builders you enjoy. Your builds inspire others!",
                color: Color.legoOrange
            )
            .padding(.horizontal)
            .padding(.top, 8)

            // Filter picker
            Picker("Filter", selection: $viewModel.selectedFilter) {
                ForEach(CommunityViewModel.FeedFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if communityService.isLoading && communityService.posts.isEmpty {
                Spacer()
                ProgressView("Loading community builds...")
                Spacer()
            } else if viewModel.filteredPosts.isEmpty {
                emptyState
            } else {
                feedGrid
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search builds...")
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await communityService.loadCurrentProfile()
            await viewModel.refresh()
        }
    }

    // MARK: - Feed Grid

    private var feedGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.filteredPosts) { post in
                    CommunityPostCard(post: post) {
                        viewModel.toggleLike(postId: post.id)
                    }
                    .onTapGesture {
                        selectedPost = post
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                viewModel.selectedFilter == .myPosts ? "No Posts Yet" : "No Builds Found",
                systemImage: viewModel.selectedFilter == .myPosts ? "photo.on.rectangle.angled" : "magnifyingglass"
            )
        } description: {
            if viewModel.selectedFilter == .myPosts {
                Text("Share your first build with the community!")
            } else if !viewModel.searchText.isEmpty {
                Text("Try a different search term.")
            } else {
                Text("Be the first to share a build!")
            }
        } actions: {
            if viewModel.selectedFilter == .myPosts {
                Button("Share a Build") {
                    showShareCreation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.legoBlue)
            }
        }
    }

    // MARK: - Sign In Prompt

    private var signInPrompt: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.3.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.legoBlue)

            Text("Join the Community")
                .font(.title2)
                .fontWeight(.bold)

            Text("Sign in to share your builds, discover creations from other builders, and save your favorites.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { _ in }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .frame(maxWidth: 280)
            .onAppear {
                // Use our AuthenticationService instead
            }

            Button("Sign In with Apple") {
                auth.signIn()
            }
            .buttonStyle(.borderedProminent)
            .tint(.black)
            .controlSize(.large)

            if auth.isLoading {
                ProgressView()
            }

            if let error = auth.authError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Post Card

struct CommunityPostCard: View {
    let post: CommunityPost
    let onLike: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image or placeholder
            ZStack {
                if let imageData = post.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [Color.legoBlue.opacity(0.3), Color.legoBlue.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: post.category?.systemImage ?? "cube.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.legoBlue)
                }
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Title
            Text(post.projectName)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)

            // Author
            HStack(spacing: 4) {
                Image(systemName: post.authorAvatar)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(post.authorName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Difficulty + Likes
            HStack {
                if let difficulty = post.difficulty {
                    Text(difficulty.rawValue.capitalized)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(difficultyColor(difficulty).opacity(0.15))
                        )
                        .foregroundStyle(difficultyColor(difficulty))
                }

                Spacer()

                HStack(spacing: 8) {
                    // Comment count
                    HStack(spacing: 2) {
                        Image(systemName: "bubble.right")
                            .foregroundStyle(.secondary)
                        Text("\(post.commentCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Like button
                    Button {
                        onLike()
                        HapticManager.selection()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: post.isLikedByCurrentUser ? "heart.fill" : "heart")
                                .foregroundStyle(post.isLikedByCurrentUser ? Color.legoRed : .secondary)
                            Text("\(post.likeCount)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(post.projectName) by \(post.authorName), \(post.likeCount) likes")
    }

    private func difficultyColor(_ difficulty: Difficulty) -> Color {
        switch difficulty {
        case .beginner: return Color.legoGreen
        case .easy: return Color.legoBlue
        case .medium: return Color.legoYellow
        case .hard: return Color.legoOrange
        case .expert: return Color.legoRed
        }
    }
}

// MARK: - Post Detail View

struct CommunityPostDetailView: View {
    let post: CommunityPost
    @ObservedObject private var communityService = CloudKitCommunityService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Image
                if let imageData = post.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [Color.legoBlue, Color.legoBlue.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 200)
                        Image(systemName: post.category?.systemImage ?? "cube.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.white)
                    }
                }

                // Author info
                HStack(spacing: 10) {
                    Image(systemName: post.authorAvatar)
                        .font(.title2)
                        .foregroundStyle(Color.legoBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.authorName)
                            .font(.headline)
                        Text(post.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // Project info
                HStack(spacing: 8) {
                    if let category = post.category {
                        Label(category.rawValue.capitalized, systemImage: category.systemImage)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.legoBlue.opacity(0.1)))
                            .foregroundStyle(Color.legoBlue)
                    }
                    if let difficulty = post.difficulty {
                        Text(difficulty.rawValue.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.legoOrange.opacity(0.1)))
                            .foregroundStyle(Color.legoOrange)
                    }
                }

                // Caption
                if !post.caption.isEmpty {
                    Text(post.caption)
                        .font(.body)
                }

                // Comments
                CommentsView(postId: post.id)

                // Like button
                HStack {
                    Button {
                        Task {
                            await communityService.toggleLike(postId: post.id)
                        }
                        HapticManager.impact(.medium)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: post.isLikedByCurrentUser ? "heart.fill" : "heart")
                            Text("\(post.likeCount)")
                        }
                        .font(.headline)
                        .foregroundStyle(post.isLikedByCurrentUser ? Color.legoRed : .secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    ShareLink(
                        item: "Check out \"\(post.projectName)\" on \(AppConfig.appName)! #BrickVision #LEGO",
                        subject: Text(post.projectName),
                        message: Text(post.caption)
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle(post.projectName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}

import AuthenticationServices
