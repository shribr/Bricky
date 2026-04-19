import Foundation

/// A community post representing a shared build creation or submitted build idea
struct CommunityPost: Identifiable, Codable {
    let id: String               // CloudKit record name
    let authorId: String         // Apple user identifier
    var authorName: String
    var authorAvatar: String     // SF Symbol name
    var projectName: String
    var projectCategory: String  // ProjectCategory raw value
    var projectDifficulty: String // Difficulty raw value
    var caption: String
    var imageData: Data?         // JPEG photo of the build
    var likeCount: Int
    var commentCount: Int
    var isLikedByCurrentUser: Bool  // local-only, not persisted to CloudKit
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        authorId: String,
        authorName: String,
        authorAvatar: String = "person.crop.circle.fill",
        projectName: String,
        projectCategory: String,
        projectDifficulty: String,
        caption: String = "",
        imageData: Data? = nil,
        likeCount: Int = 0,
        commentCount: Int = 0,
        isLikedByCurrentUser: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.authorId = authorId
        self.authorName = authorName
        self.authorAvatar = authorAvatar
        self.projectName = projectName
        self.projectCategory = projectCategory
        self.projectDifficulty = projectDifficulty
        self.caption = caption
        self.imageData = imageData
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.isLikedByCurrentUser = isLikedByCurrentUser
        self.createdAt = createdAt
    }

    /// Category enum value, if parseable
    var category: ProjectCategory? {
        ProjectCategory(rawValue: projectCategory)
    }

    /// Difficulty enum value, if parseable
    var difficulty: Difficulty? {
        Difficulty(rawValue: projectDifficulty)
    }
}
