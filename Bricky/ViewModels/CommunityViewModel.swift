import Foundation
import SwiftUI

/// View model for the community feed, managing post display and filtering
final class CommunityViewModel: ObservableObject {
    @Published var selectedFilter: FeedFilter = .recent
    @Published var searchText: String = ""

    enum FeedFilter: String, CaseIterable {
        case recent = "Recent"
        case popular = "Popular"
        case myPosts = "My Posts"
    }

    var filteredPosts: [CommunityPost] {
        let service = CloudKitCommunityService.shared
        var result = service.posts

        // Apply filter
        switch selectedFilter {
        case .recent:
            result.sort { $0.createdAt > $1.createdAt }
        case .popular:
            result.sort { $0.likeCount > $1.likeCount }
        case .myPosts:
            let userId = AuthenticationService.shared.userIdentifier
            result = result.filter { $0.authorId == userId }
        }

        // Apply search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.projectName.lowercased().contains(query) ||
                $0.authorName.lowercased().contains(query) ||
                $0.caption.lowercased().contains(query)
            }
        }

        return result
    }

    func refresh() async {
        await CloudKitCommunityService.shared.fetchPosts()
    }

    func toggleLike(postId: String) {
        Task {
            await CloudKitCommunityService.shared.toggleLike(postId: postId)
        }
    }
}
