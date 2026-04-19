import SwiftUI

/// Comment thread view for community posts
struct CommentsView: View {
    let postId: String
    @ObservedObject private var communityService = CloudKitCommunityService.shared
    @ObservedObject private var authService = AuthenticationService.shared
    @State private var comments: [Comment] = []
    @State private var newCommentText = ""
    @State private var isLoading = true
    @State private var isSending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundStyle(Color.legoRed)
                Text("Comments")
                    .font(.headline)
                if !comments.isEmpty {
                    Text("(\(comments.count))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else if comments.isEmpty {
                Text("No comments yet. Be the first!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                ForEach(comments) { comment in
                    CommentRow(
                        comment: comment,
                        canDelete: comment.authorId == authService.userIdentifier,
                        onDelete: {
                            Task { await deleteComment(comment) }
                        }
                    )
                }
            }

            if authService.isSignedIn {
                commentInput
            } else {
                Text("Sign in to comment")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await loadComments()
        }
    }

    private var commentInput: some View {
        HStack(spacing: 8) {
            TextField("Add a comment...", text: $newCommentText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)

            Button {
                Task { await sendComment() }
            } label: {
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(Color.legoRed)
                }
            }
            .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
    }

    private func loadComments() async {
        comments = await communityService.fetchComments(for: postId)
        isLoading = false
    }

    private func sendComment() async {
        let text = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isSending = true
        do {
            try await communityService.addComment(postId: postId, text: text)
            newCommentText = ""
            await loadComments()
        } catch {
            // Comment failed silently
        }
        isSending = false
    }

    private func deleteComment(_ comment: Comment) async {
        do {
            try await communityService.deleteComment(comment.id, postId: postId)
            comments.removeAll { $0.id == comment.id }
        } catch {
            // Delete failed silently
        }
    }
}

/// Individual comment row
struct CommentRow: View {
    let comment: Comment
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: comment.authorAvatar)
                .font(.title3)
                .foregroundStyle(Color.legoRed)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(comment.authorName)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(comment.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(comment.text)
                    .font(.subheadline)
            }

            if canDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
