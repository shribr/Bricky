import Foundation

/// User profile for community features
struct UserProfile: Identifiable, Codable {
    let id: String           // Apple user identifier
    var username: String
    var displayName: String
    var bio: String
    var avatarSystemName: String  // SF Symbol name
    var buildCount: Int
    var likeCount: Int
    var followerCount: Int
    var followingCount: Int
    let joinDate: Date

    init(
        id: String,
        username: String = "",
        displayName: String = "",
        bio: String = "",
        avatarSystemName: String = "person.crop.circle.fill",
        buildCount: Int = 0,
        likeCount: Int = 0,
        followerCount: Int = 0,
        followingCount: Int = 0,
        joinDate: Date = Date()
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.bio = bio
        self.avatarSystemName = avatarSystemName
        self.buildCount = buildCount
        self.likeCount = likeCount
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.joinDate = joinDate
    }
}

/// Available avatar choices for user profiles
enum ProfileAvatar: String, CaseIterable, Identifiable {
    case person = "person.crop.circle.fill"
    case brick = "cube.fill"
    case hammer = "hammer.fill"
    case star = "star.fill"
    case heart = "heart.fill"
    case bolt = "bolt.fill"
    case crown = "crown.fill"
    case flame = "flame.fill"
    case leaf = "leaf.fill"
    case gear = "gearshape.fill"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .person: return "Person"
        case .brick: return "Brick"
        case .hammer: return "Builder"
        case .star: return "Star"
        case .heart: return "Heart"
        case .bolt: return "Lightning"
        case .crown: return "Crown"
        case .flame: return "Flame"
        case .leaf: return "Nature"
        case .gear: return "Gear"
        }
    }
}
