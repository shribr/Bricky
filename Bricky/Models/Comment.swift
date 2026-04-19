import Foundation

/// A comment on a community post
struct Comment: Identifiable, Codable {
    var id: String
    var postId: String
    var authorId: String
    var authorName: String
    var authorAvatar: String
    var text: String
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        postId: String,
        authorId: String,
        authorName: String,
        authorAvatar: String = "person.crop.circle.fill",
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.postId = postId
        self.authorId = authorId
        self.authorName = authorName
        self.authorAvatar = authorAvatar
        self.text = text
        self.createdAt = createdAt
    }
}
