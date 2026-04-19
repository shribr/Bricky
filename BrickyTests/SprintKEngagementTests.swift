import XCTest
@testable import Bricky

// MARK: - Comment Model Tests

final class CommentTests: XCTestCase {

    func testCommentDefaultInit() {
        let comment = Comment(postId: "post1", authorId: "user1", authorName: "Builder", text: "Nice build!")
        XCTAssertFalse(comment.id.isEmpty)
        XCTAssertEqual(comment.postId, "post1")
        XCTAssertEqual(comment.authorId, "user1")
        XCTAssertEqual(comment.authorName, "Builder")
        XCTAssertEqual(comment.authorAvatar, "person.crop.circle.fill")
        XCTAssertEqual(comment.text, "Nice build!")
    }

    func testCommentCustomInit() {
        let date = Date(timeIntervalSince1970: 5000)
        let comment = Comment(
            id: "c1",
            postId: "post2",
            authorId: "user2",
            authorName: "Jane",
            authorAvatar: "star.fill",
            text: "Great work!",
            createdAt: date
        )
        XCTAssertEqual(comment.id, "c1")
        XCTAssertEqual(comment.authorAvatar, "star.fill")
        XCTAssertEqual(comment.createdAt, date)
    }

    func testCommentCodable() throws {
        let comment = Comment(postId: "p1", authorId: "u1", authorName: "Test", text: "Hello")
        let data = try JSONEncoder().encode(comment)
        let decoded = try JSONDecoder().decode(Comment.self, from: data)
        XCTAssertEqual(decoded.id, comment.id)
        XCTAssertEqual(decoded.postId, comment.postId)
        XCTAssertEqual(decoded.authorId, comment.authorId)
        XCTAssertEqual(decoded.text, comment.text)
    }

    func testCommentIdentifiable() {
        let c1 = Comment(postId: "p", authorId: "u", authorName: "A", text: "x")
        let c2 = Comment(postId: "p", authorId: "u", authorName: "A", text: "y")
        XCTAssertNotEqual(c1.id, c2.id)
    }
}

// MARK: - DailyChallenge Model Tests

final class DailyChallengeTests: XCTestCase {

    func testDailyChallengeDefaultInit() {
        let challenge = DailyChallenge(
            projectName: "Castle",
            projectCategory: "Buildings",
            projectDifficulty: "Medium",
            estimatedTime: "25 min",
            imageSystemName: "building.columns",
            pieceCount: 50
        )
        XCTAssertEqual(challenge.projectName, "Castle")
        XCTAssertEqual(challenge.projectCategory, "Buildings")
        XCTAssertEqual(challenge.pieceCount, 50)
        XCTAssertFalse(challenge.isCompleted)
        XCTAssertNil(challenge.completionTime)
        XCTAssertNil(challenge.startedAt)
    }

    func testDailyChallengeDateKey() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.date(from: "2025-03-15")!
        let challenge = DailyChallenge(
            date: date,
            projectName: "Test",
            projectCategory: "Art & Mosaic",
            projectDifficulty: "Easy",
            estimatedTime: "10 min",
            imageSystemName: "cube",
            pieceCount: 10
        )
        XCTAssertEqual(challenge.dateKey, "2025-03-15")
    }

    func testDailyChallengeFormattedCompletionTime() {
        var challenge = DailyChallenge(
            projectName: "Test",
            projectCategory: "Vehicles",
            projectDifficulty: "Hard",
            estimatedTime: "30 min",
            imageSystemName: "car",
            pieceCount: 80
        )
        XCTAssertNil(challenge.formattedCompletionTime)

        challenge.completionTime = 323 // 5 minutes 23 seconds
        XCTAssertEqual(challenge.formattedCompletionTime, "5:23")

        challenge.completionTime = 60
        XCTAssertEqual(challenge.formattedCompletionTime, "1:00")
    }

    func testDailyChallengeCodable() throws {
        let challenge = DailyChallenge(
            projectName: "Tower",
            projectCategory: "Buildings",
            projectDifficulty: "Expert",
            estimatedTime: "45 min",
            imageSystemName: "building",
            pieceCount: 120,
            isCompleted: true,
            completionTime: 2400
        )
        let data = try JSONEncoder().encode(challenge)
        let decoded = try JSONDecoder().decode(DailyChallenge.self, from: data)
        XCTAssertEqual(decoded.projectName, "Tower")
        XCTAssertEqual(decoded.pieceCount, 120)
        XCTAssertTrue(decoded.isCompleted)
        XCTAssertEqual(decoded.completionTime, 2400)
    }
}

// MARK: - BuildPuzzle Model Tests

final class BuildPuzzleTests: XCTestCase {

    private func makeSampleProject() -> LegoProject {
        LegoProject(
            name: "Test Racer",
            description: "A test racer",
            difficulty: .medium,
            category: .vehicle,
            estimatedTime: "20 min",
            requiredPieces: [],
            instructions: [],
            imageSystemName: "car.fill"
        )
    }

    func testBuildPuzzleInit() {
        let project = makeSampleProject()
        let puzzle = BuildPuzzle(project: project, clues: ["Clue 1", "Clue 2", "Clue 3"])
        XCTAssertEqual(puzzle.project.name, "Test Racer")
        XCTAssertEqual(puzzle.clues.count, 3)
        XCTAssertEqual(puzzle.revealedClues, 1)
        XCTAssertFalse(puzzle.isGuessed)
        XCTAssertEqual(puzzle.attempts, 0)
    }

    func testBuildPuzzleCurrentClue() {
        let project = makeSampleProject()
        let puzzle = BuildPuzzle(project: project, clues: ["First", "Second", "Third"])
        XCTAssertEqual(puzzle.currentClue, "First")
    }

    func testBuildPuzzleAllRevealedClues() {
        let project = makeSampleProject()
        var puzzle = BuildPuzzle(project: project, clues: ["A", "B", "C"])
        XCTAssertEqual(puzzle.allRevealedClues, ["A"])
        puzzle.revealedClues = 2
        XCTAssertEqual(puzzle.allRevealedClues, ["A", "B"])
        puzzle.revealedClues = 3
        XCTAssertEqual(puzzle.allRevealedClues, ["A", "B", "C"])
    }

    func testBuildPuzzleCanRevealMore() {
        let project = makeSampleProject()
        var puzzle = BuildPuzzle(project: project, clues: ["A", "B"])
        XCTAssertTrue(puzzle.canRevealMore)
        puzzle.revealedClues = 2
        XCTAssertFalse(puzzle.canRevealMore)
    }

    func testBuildPuzzleScoreMaxWhenFirstClue() {
        let project = makeSampleProject()
        var puzzle = BuildPuzzle(project: project, clues: ["A", "B", "C", "D", "E"])
        puzzle.isGuessed = true
        // revealedClues=1, attempts=0 → 100 - 0 - 0 = 100
        XCTAssertEqual(puzzle.score, 100)
    }

    func testBuildPuzzleScoreDecreaseWithClues() {
        let project = makeSampleProject()
        var puzzle = BuildPuzzle(project: project, clues: ["A", "B", "C", "D", "E"])
        puzzle.revealedClues = 3
        puzzle.isGuessed = true
        // 100 - (3-1)*20 - 0*5 = 100 - 40 = 60
        XCTAssertEqual(puzzle.score, 60)
    }

    func testBuildPuzzleScoreDecreaseWithAttempts() {
        let project = makeSampleProject()
        var puzzle = BuildPuzzle(project: project, clues: ["A", "B", "C", "D", "E"])
        puzzle.attempts = 4
        puzzle.isGuessed = true
        // 100 - 0 - 4*5 = 80
        XCTAssertEqual(puzzle.score, 80)
    }

    func testBuildPuzzleScoreMinimum() {
        let project = makeSampleProject()
        var puzzle = BuildPuzzle(project: project, clues: ["A", "B", "C", "D", "E"])
        puzzle.revealedClues = 5
        puzzle.attempts = 10
        puzzle.isGuessed = true
        // 100 - (5-1)*20 - 10*5 = 100 - 80 - 50 = -30 → max(-30, 10) = 10
        XCTAssertEqual(puzzle.score, 10)
    }

    func testBuildPuzzleScoreZeroWhenNotGuessed() {
        let project = makeSampleProject()
        let puzzle = BuildPuzzle(project: project, clues: ["A"])
        XCTAssertEqual(puzzle.score, 0)
    }
}

// MARK: - UserProfile Follow Fields Tests

final class UserProfileFollowFieldsTests: XCTestCase {

    func testUserProfileFollowDefaults() {
        let profile = UserProfile(id: "test_follow_user")
        XCTAssertEqual(profile.followerCount, 0)
        XCTAssertEqual(profile.followingCount, 0)
    }

    func testUserProfileFollowCustomInit() {
        let profile = UserProfile(
            id: "follow_user",
            followerCount: 15,
            followingCount: 8
        )
        XCTAssertEqual(profile.followerCount, 15)
        XCTAssertEqual(profile.followingCount, 8)
    }

    func testUserProfileFollowMutability() {
        var profile = UserProfile(id: "mut_follow")
        profile.followerCount = 100
        profile.followingCount = 50
        XCTAssertEqual(profile.followerCount, 100)
        XCTAssertEqual(profile.followingCount, 50)
    }

    func testUserProfileFollowCodable() throws {
        let profile = UserProfile(
            id: "codable_follow",
            username: "FollowTest",
            followerCount: 25,
            followingCount: 12
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        XCTAssertEqual(decoded.followerCount, 25)
        XCTAssertEqual(decoded.followingCount, 12)
    }
}

// MARK: - StreakTracker Tests

final class StreakTrackerTests: XCTestCase {

    func testStreakTrackerSingleton() {
        let tracker = StreakTracker.shared
        XCTAssertNotNil(tracker)
    }

    func testStreakTrackerIsActiveToday() {
        let tracker = StreakTracker.shared
        // After recording activity, isActiveToday should be true
        tracker.recordActivity()
        XCTAssertTrue(tracker.isActiveToday)
    }

    func testStreakTrackerRecordActivitySetsStreak() {
        let tracker = StreakTracker.shared
        tracker.reset()
        XCTAssertEqual(tracker.currentStreak, 0)
        tracker.recordActivity()
        XCTAssertEqual(tracker.currentStreak, 1)
    }

    func testStreakTrackerDuplicateRecordSameDay() {
        let tracker = StreakTracker.shared
        tracker.reset()
        tracker.recordActivity()
        XCTAssertEqual(tracker.currentStreak, 1)
        // Recording again on same day shouldn't change streak
        tracker.recordActivity()
        XCTAssertEqual(tracker.currentStreak, 1)
    }

    func testStreakTrackerLongestStreak() {
        let tracker = StreakTracker.shared
        tracker.reset()
        tracker.recordActivity()
        XCTAssertGreaterThanOrEqual(tracker.longestStreak, tracker.currentStreak)
    }

    func testStreakTrackerReset() {
        let tracker = StreakTracker.shared
        tracker.recordActivity()
        tracker.reset()
        XCTAssertEqual(tracker.currentStreak, 0)
        XCTAssertEqual(tracker.longestStreak, 0)
        XCTAssertNil(tracker.lastActiveDate)
    }

    func testStreakTrackerStatusMessage() {
        let tracker = StreakTracker.shared
        tracker.reset()
        XCTAssertEqual(tracker.statusMessage, "Start building to begin a streak!")
        tracker.recordActivity()
        XCTAssertTrue(tracker.statusMessage.contains("1 day streak"))
    }
}

// MARK: - SidebarTab Games Tests

final class SidebarTabGamesTests: XCTestCase {

    func testGamesTabExists() {
        let allTabs = AdaptiveSplitView.SidebarTab.allCases
        XCTAssertTrue(allTabs.map(\.rawValue).contains("Games"))
    }

    func testGamesTabIcon() {
        XCTAssertEqual(AdaptiveSplitView.SidebarTab.games.icon, "puzzlepiece.fill")
    }

    func testSidebarTabCountIncludesGames() {
        XCTAssertEqual(AdaptiveSplitView.SidebarTab.allCases.count, 7)
    }
}

// MARK: - CommunityPost CommentCount Tests

final class CommunityPostCommentCountTests: XCTestCase {

    func testCommunityPostCommentCountDefault() {
        let post = CommunityPost(
            authorId: "user1",
            authorName: "Builder",
            projectName: "Test Build",
            projectCategory: "Vehicles",
            projectDifficulty: "Medium"
        )
        XCTAssertEqual(post.commentCount, 0)
    }

    func testCommunityPostCommentCountMutable() {
        var post = CommunityPost(
            authorId: "user1",
            authorName: "Builder",
            projectName: "Test Build",
            projectCategory: "Vehicles",
            projectDifficulty: "Medium",
            commentCount: 5
        )
        XCTAssertEqual(post.commentCount, 5)
        post.commentCount = 10
        XCTAssertEqual(post.commentCount, 10)
    }
}

// MARK: - PuzzleEngine Tests

final class PuzzleEngineTests: XCTestCase {

    func testPuzzleEngineSingleton() {
        let engine = PuzzleEngine.shared
        XCTAssertNotNil(engine)
    }

    func testPuzzleEngineGeneratePuzzle() {
        let engine = PuzzleEngine.shared
        engine.generatePuzzle()
        // If there are projects available, a puzzle should be generated
        if !BuildSuggestionEngine.shared.allProjects.isEmpty {
            XCTAssertNotNil(engine.currentPuzzle)
            XCTAssertEqual(engine.currentPuzzle?.revealedClues, 1)
            XCTAssertFalse(engine.currentPuzzle?.isGuessed ?? true)
        }
    }

    func testPuzzleEngineRevealClue() {
        let engine = PuzzleEngine.shared
        engine.generatePuzzle()
        guard engine.currentPuzzle != nil else { return }
        let initialClues = engine.currentPuzzle!.revealedClues
        engine.revealNextClue()
        XCTAssertEqual(engine.currentPuzzle?.revealedClues, initialClues + 1)
    }

    func testPuzzleEngineWrongGuess() {
        let engine = PuzzleEngine.shared
        engine.generatePuzzle()
        guard engine.currentPuzzle != nil else { return }
        let result = engine.submitGuess("DEFINITELY_WRONG_ANSWER_12345")
        XCTAssertFalse(result)
        XCTAssertEqual(engine.currentPuzzle?.attempts, 1)
    }

    func testPuzzleEngineCorrectGuess() {
        let engine = PuzzleEngine.shared
        engine.generatePuzzle()
        guard let puzzle = engine.currentPuzzle else { return }
        let result = engine.submitGuess(puzzle.project.name)
        XCTAssertTrue(result)
        XCTAssertTrue(engine.currentPuzzle?.isGuessed ?? false)
    }

    func testPuzzleEngineGiveUp() {
        let engine = PuzzleEngine.shared
        engine.generatePuzzle()
        guard engine.currentPuzzle != nil else { return }
        engine.giveUp()
        XCTAssertTrue(engine.currentPuzzle?.isGuessed ?? false)
    }

    func testPuzzleEngineGetAnswerChoices() {
        let engine = PuzzleEngine.shared
        engine.generatePuzzle()
        guard let puzzle = engine.currentPuzzle else { return }
        let choices = engine.getAnswerChoices(for: puzzle, count: 4)
        XCTAssertLessThanOrEqual(choices.count, 4)
        // Correct answer should be in choices
        XCTAssertTrue(choices.contains(puzzle.project.name))
    }
}

// MARK: - DailyChallengeService Tests

final class DailyChallengeServiceTests: XCTestCase {

    func testDailyChallengeServiceSingleton() {
        let service = DailyChallengeService.shared
        XCTAssertNotNil(service)
    }

    func testDailyChallengeServiceGeneratesTodayChallenge() {
        let service = DailyChallengeService.shared
        service.generateTodayChallenge()
        if !BuildSuggestionEngine.shared.allProjects.isEmpty {
            XCTAssertNotNil(service.todayChallenge)
        }
    }

    func testDailyChallengeServiceDeterministic() {
        let service = DailyChallengeService.shared
        service.generateTodayChallenge()
        let first = service.todayChallenge?.projectName
        service.generateTodayChallenge()
        let second = service.todayChallenge?.projectName
        XCTAssertEqual(first, second, "Same day should produce same challenge")
    }

    func testDailyChallengeServiceCompletedCount() {
        let service = DailyChallengeService.shared
        XCTAssertGreaterThanOrEqual(service.completedCount, 0)
    }
}
