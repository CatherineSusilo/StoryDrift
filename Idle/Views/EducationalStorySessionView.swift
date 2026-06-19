import SwiftUI

// MARK: - EducationalStorySessionView
//
// Pregenerates an educational story + baked minigames via /api/generate/story
// (mode: "educational"), then hands off to StoryPlaybackView which plays
// paragraph-by-paragraph and triggers the baked minigame at each requested slot.

struct EducationalStorySessionView: View {
    let child: ChildProfile
    let lesson: LessonDefinition
    let minigameFrequency: MinigameFrequency
    let onComplete: (EducationalSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var eyeTracking: EyeTrackingManager

    @State private var phase: SessionPhase = .loading
    @State private var story: Story? = nil
    @State private var minigames: [BakedMinigame] = []

    enum SessionPhase {
        case loading
        case playing
        case error(String)
    }

    var body: some View {
        ZStack {
            switch phase {
            case .loading:
                LoadingView()
            case .playing:
                if let story = story {
                    StoryPlaybackView(story: story,
                                      bakedMinigames: minigames,
                                      mode: .educational) { _, duration, progress in
                        Task { await finalize(story: story, duration: duration, progress: progress) }
                    }
                    .environmentObject(authManager)
                    .environmentObject(eyeTracking)
                }
            case .error(let msg):
                errorView(msg)
            }
        }
        .onAppear { Task { await startSession() } }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text(msg)
                .font(.custom("Georgia", size: 17))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Close") { dismiss() }
                .foregroundColor(.white)
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(Capsule().fill(Color.white.opacity(0.2)))
        }
    }

    // MARK: - Generation

    private func startSession() async {
        guard let token = authManager.accessToken else {
            phase = .error("Not signed in")
            return
        }

        // Prefer curriculumLessonId from LessonDefinition, fall back to legacy UserDefaults key.
        let curriculumLessonId: String? =
            lesson.curriculumLessonId
            ?? UserDefaults.standard.string(forKey: "pendingCurriculumLessonId")
        UserDefaults.standard.removeObject(forKey: "pendingCurriculumLessonId")

        let parentPrompt =
            "An educational story that teaches \(lesson.name). " +
            "Concept detail: \(lesson.description.isEmpty ? lesson.name : lesson.description)."

        let config = StoryConfig(
            childId: child.id,
            name: child.name,
            age: child.age,
            storytellingTone: "adventurous",
            parentPrompt: parentPrompt,
            initialState: "normal",
            drawingPrompts: nil,
            characters: nil,
            minigameFrequency: minigameFrequency.rawValue,
            targetDuration: 15,
            cameraEnabled: eyeTracking.isCameraEnabled,
            mode: "educational",
            lessonName: lesson.name,
            lessonDescription: lesson.description,
            curriculumLessonId: curriculumLessonId
        )

        do {
            let (story, baked) = try await APIService.shared.generateStoryAndMinigames(
                config: config, token: token)
            print("📚 Educational story ready — \(baked.count) minigames baked")
            await MainActor.run {
                self.story = story
                self.minigames = baked
                self.phase = .playing
            }
        } catch {
            await MainActor.run {
                self.phase = .error("Could not start lesson: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Finalize

    private func finalize(story: Story, duration: TimeInterval, progress: Int) async {
        // Educational sessions don't track drift. Progress comes from how many
        // paragraphs the child reached. Mark the story complete server-side so it
        // appears in the archive with the correct duration.
        if let token = authManager.accessToken {
            try? await APIService.shared.updateStory(
                storyId: story.id, completed: progress >= 100,
                duration: Int(duration), finalDriftScore: 0,
                driftScoreHistory: [], token: token
            )
        }

        let summary = EducationalSummary(
            lessonName: lesson.name,
            lessonEmoji: lesson.emoji,
            lessonProgress: progress,
            engagementHistory: [],
            sessionDurationSeconds: Int(duration)
        )
        await MainActor.run {
            onComplete(summary)
            dismiss()
        }
    }
}

// MARK: - Summary model

struct EducationalSummary {
    let lessonName: String
    let lessonEmoji: String
    let lessonProgress: Int
    let engagementHistory: [Int]
    let sessionDurationSeconds: Int
}
