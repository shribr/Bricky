import CloudKit
import Foundation

/// CloudKit-backed service for community features: profiles, posts, likes
final class CloudKitCommunityService: ObservableObject {
    static let shared = CloudKitCommunityService()

    @Published var posts: [CommunityPost] = []
    @Published var userProfile: UserProfile?
    @Published var isLoading: Bool = false
    @Published var error: String?

    private let container = CKContainer(identifier: AppConfig.iCloudContainer)
    private var publicDB: CKDatabase { container.publicCloudDatabase }

    // CloudKit record types
    static let profileRecordType = "UserProfile"
    static let postRecordType = "CommunityPost"
    static let likeRecordType = "PostLike"
    static let commentRecordType = "Comment"
    static let followRecordType = "Follow"

    private init() {}

    // MARK: - CloudKit Availability

    var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    func checkAccountStatus() async -> Bool {
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            return false
        }
    }

    // MARK: - User Profile

    func fetchProfile(for userId: String) async -> UserProfile? {
        let recordId = CKRecord.ID(recordName: "profile_\(userId)")
        do {
            let record = try await publicDB.record(for: recordId)
            return profileFromRecord(record)
        } catch {
            return nil
        }
    }

    func saveProfile(_ profile: UserProfile) async throws {
        let recordId = CKRecord.ID(recordName: "profile_\(profile.id)")
        let record: CKRecord
        do {
            record = try await publicDB.record(for: recordId)
        } catch {
            record = CKRecord(recordType: Self.profileRecordType, recordID: recordId)
        }

        record["userId"] = profile.id
        record["username"] = profile.username
        record["displayName"] = profile.displayName
        record["bio"] = profile.bio
        record["avatarSystemName"] = profile.avatarSystemName
        record["buildCount"] = profile.buildCount
        record["likeCount"] = profile.likeCount
        record["followerCount"] = profile.followerCount
        record["followingCount"] = profile.followingCount
        record["joinDate"] = profile.joinDate

        let saved = try await publicDB.save(record)
        let updatedProfile = profileFromRecord(saved)
        await MainActor.run {
            self.userProfile = updatedProfile
        }
    }

    func loadCurrentProfile() async {
        guard let userId = AuthenticationService.shared.userIdentifier else { return }
        let profile = await fetchProfile(for: userId)
        await MainActor.run {
            if let profile {
                self.userProfile = profile
            } else {
                // Create default profile for new user
                self.userProfile = UserProfile(
                    id: userId,
                    username: AuthenticationService.shared.displayName ?? "Builder",
                    displayName: AuthenticationService.shared.displayName ?? "Builder"
                )
            }
        }
    }

    // MARK: - Community Posts

    func fetchPosts(limit: Int = 50) async {
        await MainActor.run { isLoading = true; error = nil }

        let query = CKQuery(recordType: Self.postRecordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        do {
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: limit)
            let currentUserId = AuthenticationService.shared.userIdentifier

            var fetchedPosts: [CommunityPost] = []
            for (_, result) in results {
                if let record = try? result.get() {
                    var post = postFromRecord(record)
                    if let currentUserId {
                        post.isLikedByCurrentUser = await hasUserLiked(postId: post.id, userId: currentUserId)
                    }
                    fetchedPosts.append(post)
                }
            }

            let finalPosts = fetchedPosts
            await MainActor.run {
                self.posts = finalPosts
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func createPost(_ post: CommunityPost) async throws {
        let record = CKRecord(recordType: Self.postRecordType, recordID: CKRecord.ID(recordName: post.id))
        record["authorId"] = post.authorId
        record["authorName"] = post.authorName
        record["authorAvatar"] = post.authorAvatar
        record["projectName"] = post.projectName
        record["projectCategory"] = post.projectCategory
        record["projectDifficulty"] = post.projectDifficulty
        record["caption"] = post.caption
        record["likeCount"] = 0
        record["commentCount"] = 0
        record["createdAt"] = post.createdAt

        if let imageData = post.imageData {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(post.id).jpg")
            try imageData.write(to: tempURL)
            record["image"] = CKAsset(fileURL: tempURL)
        }

        try await publicDB.save(record)

        // Increment author's build count
        if var profile = userProfile {
            profile.buildCount += 1
            try? await saveProfile(profile)
        }

        await MainActor.run {
            self.posts.insert(post, at: 0)
        }

        await AnalyticsService.shared.track(.scanCompleted) // track community post
    }

    func deletePost(_ postId: String) async throws {
        let recordId = CKRecord.ID(recordName: postId)
        try await publicDB.deleteRecord(withID: recordId)
        await MainActor.run {
            self.posts.removeAll { $0.id == postId }
        }
    }

    func fetchUserPosts(userId: String) async -> [CommunityPost] {
        let predicate = NSPredicate(format: "authorId == %@", userId)
        let query = CKQuery(recordType: Self.postRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        do {
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 50)
            return results.compactMap { _, result in
                guard let record = try? result.get() else { return nil }
                return postFromRecord(record)
            }
        } catch {
            return []
        }
    }

    // MARK: - Likes

    func toggleLike(postId: String) async {
        guard let userId = AuthenticationService.shared.userIdentifier else { return }

        let hasLiked = await hasUserLiked(postId: postId, userId: userId)

        if hasLiked {
            await removeLike(postId: postId, userId: userId)
        } else {
            await addLike(postId: postId, userId: userId)
        }
    }

    private func addLike(postId: String, userId: String) async {
        let likeId = "like_\(postId)_\(userId)"
        let record = CKRecord(recordType: Self.likeRecordType, recordID: CKRecord.ID(recordName: likeId))
        record["postId"] = postId
        record["userId"] = userId
        record["createdAt"] = Date()

        do {
            try await publicDB.save(record)
            await updateLikeCount(postId: postId, increment: 1)
            await MainActor.run {
                if let index = posts.firstIndex(where: { $0.id == postId }) {
                    posts[index].likeCount += 1
                    posts[index].isLikedByCurrentUser = true
                }
            }
        } catch {
            // Silently fail — optimistic UI will revert on next fetch
        }
    }

    private func removeLike(postId: String, userId: String) async {
        let likeId = "like_\(postId)_\(userId)"
        let recordId = CKRecord.ID(recordName: likeId)

        do {
            try await publicDB.deleteRecord(withID: recordId)
            await updateLikeCount(postId: postId, increment: -1)
            await MainActor.run {
                if let index = posts.firstIndex(where: { $0.id == postId }) {
                    posts[index].likeCount = max(0, posts[index].likeCount - 1)
                    posts[index].isLikedByCurrentUser = false
                }
            }
        } catch {
            // Silently fail
        }
    }

    func hasUserLiked(postId: String, userId: String) async -> Bool {
        let likeId = "like_\(postId)_\(userId)"
        let recordId = CKRecord.ID(recordName: likeId)
        do {
            _ = try await publicDB.record(for: recordId)
            return true
        } catch {
            return false
        }
    }

    private func updateLikeCount(postId: String, increment: Int) async {
        let recordId = CKRecord.ID(recordName: postId)
        do {
            let record = try await publicDB.record(for: recordId)
            let current = record["likeCount"] as? Int ?? 0
            record["likeCount"] = max(0, current + increment)
            try await publicDB.save(record)
        } catch {
            // Best-effort update
        }
    }

    // MARK: - Record Conversion

    private func profileFromRecord(_ record: CKRecord) -> UserProfile {
        UserProfile(
            id: record["userId"] as? String ?? record.recordID.recordName,
            username: record["username"] as? String ?? "Builder",
            displayName: record["displayName"] as? String ?? "Builder",
            bio: record["bio"] as? String ?? "",
            avatarSystemName: record["avatarSystemName"] as? String ?? "person.crop.circle.fill",
            buildCount: record["buildCount"] as? Int ?? 0,
            likeCount: record["likeCount"] as? Int ?? 0,
            followerCount: record["followerCount"] as? Int ?? 0,
            followingCount: record["followingCount"] as? Int ?? 0,
            joinDate: record["joinDate"] as? Date ?? record.creationDate ?? Date()
        )
    }

    private func postFromRecord(_ record: CKRecord) -> CommunityPost {
        var imageData: Data?
        if let asset = record["image"] as? CKAsset, let url = asset.fileURL {
            imageData = try? Data(contentsOf: url)
        }

        return CommunityPost(
            id: record.recordID.recordName,
            authorId: record["authorId"] as? String ?? "",
            authorName: record["authorName"] as? String ?? "Builder",
            authorAvatar: record["authorAvatar"] as? String ?? "person.crop.circle.fill",
            projectName: record["projectName"] as? String ?? "Untitled Build",
            projectCategory: record["projectCategory"] as? String ?? "decoration",
            projectDifficulty: record["projectDifficulty"] as? String ?? "medium",
            caption: record["caption"] as? String ?? "",
            imageData: imageData,
            likeCount: record["likeCount"] as? Int ?? 0,
            commentCount: record["commentCount"] as? Int ?? 0,
            createdAt: record["createdAt"] as? Date ?? record.creationDate ?? Date()
        )
    }

    // MARK: - Comments

    func fetchComments(for postId: String) async -> [Comment] {
        let predicate = NSPredicate(format: "postId == %@", postId)
        let query = CKQuery(recordType: Self.commentRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        do {
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 100)
            return results.compactMap { _, result in
                guard let record = try? result.get() else { return nil }
                return commentFromRecord(record)
            }
        } catch {
            return []
        }
    }

    func addComment(postId: String, text: String) async throws {
        guard let userId = AuthenticationService.shared.userIdentifier else { return }
        let authorName = userProfile?.username ?? AuthenticationService.shared.displayName ?? "Builder"
        let authorAvatar = userProfile?.avatarSystemName ?? "person.crop.circle.fill"

        let comment = Comment(
            postId: postId,
            authorId: userId,
            authorName: authorName,
            authorAvatar: authorAvatar,
            text: text
        )

        let record = CKRecord(recordType: Self.commentRecordType, recordID: CKRecord.ID(recordName: comment.id))
        record["postId"] = comment.postId
        record["authorId"] = comment.authorId
        record["authorName"] = comment.authorName
        record["authorAvatar"] = comment.authorAvatar
        record["text"] = comment.text
        record["createdAt"] = comment.createdAt

        try await publicDB.save(record)

        // Update comment count on the post
        await updateCommentCount(postId: postId, increment: 1)
        await MainActor.run {
            if let index = posts.firstIndex(where: { $0.id == postId }) {
                posts[index].commentCount += 1
            }
        }
    }

    func deleteComment(_ commentId: String, postId: String) async throws {
        let recordId = CKRecord.ID(recordName: commentId)
        try await publicDB.deleteRecord(withID: recordId)
        await updateCommentCount(postId: postId, increment: -1)
        await MainActor.run {
            if let index = posts.firstIndex(where: { $0.id == postId }) {
                posts[index].commentCount = max(0, posts[index].commentCount - 1)
            }
        }
    }

    private func updateCommentCount(postId: String, increment: Int) async {
        let recordId = CKRecord.ID(recordName: postId)
        do {
            let record = try await publicDB.record(for: recordId)
            let current = record["commentCount"] as? Int ?? 0
            record["commentCount"] = max(0, current + increment)
            try await publicDB.save(record)
        } catch {
            // Best-effort update
        }
    }

    private func commentFromRecord(_ record: CKRecord) -> Comment {
        Comment(
            id: record.recordID.recordName,
            postId: record["postId"] as? String ?? "",
            authorId: record["authorId"] as? String ?? "",
            authorName: record["authorName"] as? String ?? "Builder",
            authorAvatar: record["authorAvatar"] as? String ?? "person.crop.circle.fill",
            text: record["text"] as? String ?? "",
            createdAt: record["createdAt"] as? Date ?? record.creationDate ?? Date()
        )
    }

    // MARK: - Follows

    func toggleFollow(userId: String) async {
        guard let currentUserId = AuthenticationService.shared.userIdentifier,
              currentUserId != userId else { return }

        let isFollowing = await isFollowing(userId: userId)

        if isFollowing {
            await unfollow(userId: userId)
        } else {
            await follow(userId: userId)
        }
    }

    func isFollowing(userId: String) async -> Bool {
        guard let currentUserId = AuthenticationService.shared.userIdentifier else { return false }
        let followId = "follow_\(currentUserId)_\(userId)"
        let recordId = CKRecord.ID(recordName: followId)
        do {
            _ = try await publicDB.record(for: recordId)
            return true
        } catch {
            return false
        }
    }

    private func follow(userId: String) async {
        guard let currentUserId = AuthenticationService.shared.userIdentifier else { return }
        let followId = "follow_\(currentUserId)_\(userId)"
        let record = CKRecord(recordType: Self.followRecordType, recordID: CKRecord.ID(recordName: followId))
        record["followerId"] = currentUserId
        record["followeeId"] = userId
        record["createdAt"] = Date()

        do {
            try await publicDB.save(record)
            await updateFollowCounts(followerId: currentUserId, followeeId: userId, increment: 1)
        } catch {
            // Silently fail
        }
    }

    private func unfollow(userId: String) async {
        guard let currentUserId = AuthenticationService.shared.userIdentifier else { return }
        let followId = "follow_\(currentUserId)_\(userId)"
        let recordId = CKRecord.ID(recordName: followId)

        do {
            try await publicDB.deleteRecord(withID: recordId)
            await updateFollowCounts(followerId: currentUserId, followeeId: userId, increment: -1)
        } catch {
            // Silently fail
        }
    }

    private func updateFollowCounts(followerId: String, followeeId: String, increment: Int) async {
        // Update follower's followingCount
        let followerRecordId = CKRecord.ID(recordName: "profile_\(followerId)")
        do {
            let record = try await publicDB.record(for: followerRecordId)
            let current = record["followingCount"] as? Int ?? 0
            record["followingCount"] = max(0, current + increment)
            try await publicDB.save(record)
            if followerId == AuthenticationService.shared.userIdentifier {
                await MainActor.run {
                    self.userProfile?.followingCount = max(0, (self.userProfile?.followingCount ?? 0) + increment)
                }
            }
        } catch {}

        // Update followee's followerCount
        let followeeRecordId = CKRecord.ID(recordName: "profile_\(followeeId)")
        do {
            let record = try await publicDB.record(for: followeeRecordId)
            let current = record["followerCount"] as? Int ?? 0
            record["followerCount"] = max(0, current + increment)
            try await publicDB.save(record)
        } catch {}
    }

    func fetchFollowedUserIds() async -> [String] {
        guard let currentUserId = AuthenticationService.shared.userIdentifier else { return [] }
        let predicate = NSPredicate(format: "followerId == %@", currentUserId)
        let query = CKQuery(recordType: Self.followRecordType, predicate: predicate)

        do {
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 200)
            return results.compactMap { _, result in
                guard let record = try? result.get() else { return nil }
                return record["followeeId"] as? String
            }
        } catch {
            return []
        }
    }
}
