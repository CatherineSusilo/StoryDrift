import Foundation
import SwiftUI

// MARK: - Child (matches backend MongoDB schema)
struct Child: Codable, Identifiable {
    let id: String
    let userId: String?   // present in list/get responses; may be absent in some contexts
    var name: String
    var age: Int
    var dateOfBirth: Date?
    var avatar: String?
    let createdAt: Date
    let updatedAt: Date
    var preferences: ChildPreferencesModel?
}

struct ChildPreferencesModel: Codable {
    // id and childId are Prisma-only — MongoDB embeds preferences directly, no separate id
    var storytellingTone: String
    var favoriteThemes: [String]
    var defaultInitialState: String
    var personality: String?
    var favoriteMedia: String?
    var parentGoals: String?
}

// ChildProfile kept as a UI-only alias for backwards compatibility with views
typealias ChildProfile = Child


enum StorytellingTone: String, Codable, CaseIterable {
    case calming = "calming"
    case energetic = "energetic"
    case sad = "sad"
    case adventurous = "adventurous"
    case none = "none"

    var displayName: String {
        switch self {
        case .calming: return "Calming"
        case .energetic: return "Energetic"
        case .sad: return "Sad"
        case .adventurous: return "Adventurous"
        case .none: return "None"
        }
    }

    var emoji: String {
        switch self {
        case .calming: return "😌"
        case .energetic: return "⚡"
        case .sad: return "😢"
        case .adventurous: return "🗺️"
        case .none: return "✨"
        }
    }

    var icon: String {
        switch self {
        case .calming: return "wind"
        case .energetic: return "bolt.fill"
        case .sad: return "cloud.rain"
        case .adventurous: return "map.fill"
        case .none: return "circle"
        }
    }
}

enum InitialState: String, Codable, CaseIterable {
    case woundUp = "wound-up"
    case normal = "normal"
    case almostThere = "almost-there"

    var displayName: String {
        switch self {
        case .woundUp: return "Wound Up"
        case .normal: return "Normal"
        case .almostThere: return "Almost There"
        }
    }
}

struct CustomCharacter: Codable, Identifiable {
    let id: String
    var name: String
    var description: String
    var imageUrl: String?

    init(id: String = UUID().uuidString, name: String, description: String, imageUrl: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.imageUrl = imageUrl
    }
}

// MARK: - Story
// Matches backend StorySession Prisma model
struct Story: Codable, Identifiable {
    let id: String
    let childId: String
    var storyTitle: String
    var storyContent: String
    var parentPrompt: String
    var storytellingTone: String
    var initialState: String
    let startTime: Date
    var endTime: Date?
    var duration: Int?
    var sleepOnsetTime: Date?
    var completed: Bool
    var initialDriftScore: Int
    var finalDriftScore: Int
    var driftScoreHistory: [Int]
    var generatedImages: [String]
    var modelUsed: String?
    /// Per-paragraph MP3 URLs from ElevenLabs (parallel array to generatedImages).
    var audioUrls: [String]?
    /// Target duration in minutes chosen by the parent (10 / 15 / 20).
    var targetDuration: Int?
    /// Job ID for background Gemini image generation — poll /api/generate/story-images/:id
    var imageJobId: String?
    /// Minigame frequency selected at story setup.
    var minigameFrequency: String?
    /// Whether Presage face detection camera was enabled for this story.
    var cameraEnabled: Bool?
    /// Set for educational stories generated from the curriculum roadmap.
    var curriculumLessonId: String?
    let createdAt: Date
    let updatedAt: Date

    // Convenience accessors used by views
    var title: String { storyTitle }
    var images: [String] { generatedImages }
    var themes: [String] { [storytellingTone] }
    var generatedAt: Date { startTime }
    var completedAt: Date? { endTime }
    var driftScores: [Double] { driftScoreHistory.map { Double($0) } }
    /// Split storyContent into paragraphs, attaching per-paragraph image and audio URLs.
    var paragraphs: [StoryParagraph] {
        let texts = storyContent
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return texts.enumerated().map { idx, text in
            let audio = (audioUrls ?? []).indices.contains(idx)
                ? (audioUrls![idx].isEmpty ? nil : audioUrls![idx])
                : nil
            return StoryParagraph(text: text, audioUrl: audio)
        }
    }
}

struct StoryParagraph: Codable, Identifiable {
    let id: String
    var text: String
    var audioUrl: String?
    var duration: Double
    var startTime: Date?
    var isNarrated: Bool

    init(id: String = UUID().uuidString, text: String, audioUrl: String? = nil,
         duration: Double = 0, startTime: Date? = nil, isNarrated: Bool = false) {
        self.id = id
        self.text = text
        self.audioUrl = audioUrl
        self.duration = duration
        self.startTime = startTime
        self.isNarrated = isNarrated
    }
}

struct StoryScene: Codable, Identifiable {
    let id: String
    var imageUrl: String
    var prompt: String
    var paragraphIndex: Int

    init(id: String = UUID().uuidString, imageUrl: String, prompt: String, paragraphIndex: Int) {
        self.id = id
        self.imageUrl = imageUrl
        self.prompt = prompt
        self.paragraphIndex = paragraphIndex
    }
}

struct InteractiveElement: Codable, Identifiable {
    let id: String
    var type: InteractiveType
    var content: String
    var options: [String]?
    var paragraphIndex: Int
    var completed: Bool
    var response: String?
}

enum InteractiveType: String, Codable {
    case choice = "choice"
    case quiz = "quiz"
    case drawing = "drawing"
}

struct StoryMetadata: Codable {
    var targetDuration: Int
    var initialDriftScore: Double
    var finalDriftScore: Double?
    var avgHeartRate: Double?
    var avgBreathingRate: Double?
    var completionReason: String?
}

// MARK: - Drift Score
struct DriftScore: Codable, Identifiable {
    let timestamp: Date
    let score: Double
    let heartRate: Double?
    let breathingRate: Double?

    var id: String { timestamp.ISO8601Format() }
}

// MARK: - Vitals
struct Vitals: Codable {
    let childId: String
    let timestamp: Date
    let heartRate: Double
    let breathingRate: Double
    let signalQuality: Int
}

struct VitalsData: Codable, Identifiable {
    let id: String
    let childId: String
    var heartRate: Double
    var breathingRate: Double
    var signalQuality: Double
    var driftScore: Double
    let timestamp: Date
}

struct VitalsSnapshot: Codable, Identifiable {
    let date: Date
    let avgHeartRate: Double
    let avgBreathingRate: Double

    var id: String { date.ISO8601Format() }
}

// MARK: - Statistics
// Matches GET /api/statistics/stories/:childId
struct ChildStatistics: Codable {
    let childId: String
    let period: StatsPeriod
    let summary: StoryStatsSummary
    let toneDistribution: [String: Int]?
    let stateDistribution: [String: Int]?
    let storyTrend: [StoryTrendPoint]?
}

struct StatsPeriod: Codable {
    let days: Int
    let from: Date
    let to: Date
}

struct StoryStatsSummary: Codable {
    let totalSessions: Int
    let completedSessions: Int
    let avgDuration: Int
    let avgInitialDriftScore: Int?
    let avgFinalDriftScore: Int?
    let avgDriftImprovement: Double?   // avg (finalDrift - initialDrift) across completed stories
}

struct StoryTrendPoint: Codable {
    let date: String
    let count: Int?
    let avgDuration: Int
    let avgDriftImprovement: Double
}

// Matches GET /api/statistics/sleep/:childId
struct SleepStatisticsResponse: Codable {
    let childId: String
    let period: StatsPeriod
    let summary: SleepStatsSummary
    let qualityDistribution: [String: Int]?
    let sleepTrend: [SleepTrendPoint]?
}

struct SleepStatsSummary: Codable {
    let totalSessions: Int
    let completedSessions: Int
    let avgDuration: Int
    let avgTimeToSleep: Int
    let avgNightWakings: Double
    let avgSleepEfficiency: Double
}

struct SleepTrendPoint: Codable {
    let date: String
    let avgDuration: Int
    let avgTimeToSleep: Int
    let avgSleepEfficiency: Double
}

struct SleepStatistics: Codable {
    var totalStoriesCompleted: Int
    var avgTimeToSleep: Double
    var avgHeartRate: Double
    var avgBreathingRate: Double
    var avgDriftScore: Double
    var sleepTrends: [TrendData]
}

struct TrendData: Codable, Identifiable {
    let id: String
    let date: Date
    var value: Double
    var metric: String

    init(id: String = UUID().uuidString, date: Date, value: Double, metric: String) {
        self.id = id
        self.date = date
        self.value = value
        self.metric = metric
    }
}

// MARK: - API Response Types
struct APIResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let error: String?
}

struct AuthResponse: Codable {
    let token: String
    let user: User
}

struct User: Codable {
    let id: String
    let email: String
    let name: String?
    let picture: String?
    // Prisma serialises MongoDB's _id as "id" in JSON output — no custom CodingKeys needed
}

// MARK: - API Request/Response Models

struct CreateChildRequest: Codable {
    var name: String
    var age: Int
    var dateOfBirth: String?
    var avatar: String?
    var preferences: ChildPrefsRequest?
}

struct UpdateChildRequest: Codable {
    var name: String?
    var age: Int?
    var dateOfBirth: String?
    var avatar: String?
    var preferences: ChildPrefsRequest?
}

struct ChildPrefsRequest: Codable {
    var storytellingTone: String?
    var favoriteThemes: [String]?
    var defaultInitialState: String?
    var personality: String?
    var favoriteMedia: String?
    var parentGoals: String?
}

struct GenerateStoryRequest: Codable {
    var childId: String
    var theme: String
    var parentPrompt: String?
    var targetDuration: Int
}

struct PostVitalsRequest: Codable {
    var childId: String
    var heartRate: Double
    var breathingRate: Double
    var signalQuality: Double
}

struct DeleteResponse: Codable {
    let message: String
}

struct EmptyResponse: Codable {}

// MARK: - Lesson Models
struct LessonCategory: Identifiable {
    let id: String
    let title: String
    let emoji: String
    let color: Color
    let lessons: [LessonDefinition]
}

struct LessonDefinition: Identifiable {
    let id: String
    let name: String
    let description: String
    let emoji: String
    let ageMin: Int
    let ageMax: Int
    /// Set when launched from the curriculum roadmap so the backend uses the exact lesson
    var curriculumLessonId: String? = nil
}

// Matches paginated responses like GET /api/stories/child/:id → { data: [...], total, limit, offset }
struct PaginatedResponse<T: Codable>: Codable {
    let data: [T]
    let total: Int
    let limit: Int
    let offset: Int
}

// MARK: - Curriculum Models (matching backend structure)

struct CurriculumSection: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let emoji: String
    let color: String
    var lessons: [CurriculumLesson]?
    
    // For lesson list preview
    var lessonCount: Int?
}

struct CurriculumLesson: Codable, Identifiable {
    let id: String
    let order: Int
    let name: String
    let description: String
    let concepts: [String]
    let storyTheme: String?
    let expectedSegments: Int
    let minigameCount: Int?
    let unlockAfter: String?
}

struct MinigameSlot: Codable {
    let afterSegment: Int
    let preferredType: String
    let hint: String?
}

struct LessonProgress: Codable, Identifiable {
    let id: String
    let childId: String
    let lessonId: String
    let sectionId: String
    let completed: Bool
    let stars: Int
    let attempts: Int
    let bestScore: Int
    let lastSessionId: String?
    let completedAt: String?
}

struct ChildProgressResponse: Codable {
    let childId: String
    let age: Int?
    let sections: [SectionProgress]
}

struct SectionProgress: Codable {
    let id: String
    let name: String
    let emoji: String?
    let color: String?
    let totalLessons: Int
    let completedCount: Int
    let progressPct: Double?
    let lessons: [LessonProgressDetail]

    // Convenience aliases used by views
    var sectionId: String { id }
    var sectionName: String { name }
    var completedLessons: Int { completedCount }
}

struct LessonProgressDetail: Codable {
    let id: String
    let order: Int?
    let name: String
    let unlocked: Bool
    let completed: Bool
    let stars: Int
    let attempts: Int?
    let bestScore: Int?

    // Convenience aliases used by views
    var lessonId: String { id }
    var lessonName: String { name }
}

// MARK: - Minigame Models

enum MinigameFrequency: String, CaseIterable, Codable {
    case none        = "none"
    case every5th    = "every_5th"
    case every3rd    = "every_3rd"
    case everyParagraph = "every_paragraph"

    var displayName: String {
        switch self {
        case .none:             return "none"
        case .every5th:         return "every 5th"
        case .every3rd:         return "every 3rd"
        case .everyParagraph:   return "every paragraph"
        }
    }

    var icon: String {
        switch self {
        case .none:             return "minus"
        case .every5th:         return "🧩"
        case .every3rd:         return "✦"
        case .everyParagraph:   return "⭐"
        }
    }

    var usesSFSymbol: Bool { self == .none }
}

enum MinigameType: String, Codable {
    case drawing, voice, shape_sorting, multiple_choice
}

struct MinigameChoice: Codable, Identifiable {
    let id: String
    let label: String
    let emoji: String?
    let isCorrect: Bool
}

struct ShapeSlot: Codable, Identifiable {
    let id: String
    let shape: String      // circle | square | triangle | star | heart
    let color: String      // hex
    let targetSlotId: String
}

/// Wrapper for the /api/generate/minigame response envelope: { "trigger": { ... } }
struct MinigameTriggerResponse: Codable {
    let trigger: MinigameTrigger
}

struct MinigameTrigger: Codable {
    let type: MinigameType
    let narratorPrompt: String
    let drawingTheme: String?
    let drawingDarkBackground: Bool?
    let voiceTarget: String?
    let voiceHint: String?
    let choices: [MinigameChoice]?
    let shapes: [ShapeSlot]?
    let timeoutSeconds: Int?

    /// Returns a copy with a default set of shapes if type is shape_sorting and shapes is nil/empty.
    func withFallbackShapes() -> MinigameTrigger {
        guard type == .shape_sorting, (shapes ?? []).isEmpty else { return self }
        let fallback: [ShapeSlot] = [
            ShapeSlot(id: "s1", shape: "circle",   color: "#FF6B6B", targetSlotId: "slot_circle"),
            ShapeSlot(id: "s2", shape: "square",   color: "#4ECDC4", targetSlotId: "slot_square"),
            ShapeSlot(id: "s3", shape: "triangle", color: "#45B7D1", targetSlotId: "slot_triangle"),
        ]
        return MinigameTrigger(type: type, narratorPrompt: narratorPrompt,
                               drawingTheme: drawingTheme, drawingDarkBackground: drawingDarkBackground,
                               voiceTarget: voiceTarget, voiceHint: voiceHint,
                               choices: choices, shapes: fallback, timeoutSeconds: timeoutSeconds)
    }
}

struct MinigameResult {
    let type: MinigameType
    let completed: Bool
    let correct: Bool?
    let skipped: Bool
    let responseData: String?   // base64 image / transcribed word / choice id
}

// MARK: - Drawings Collection

/// A child's drawing stored in the local collection.
/// Used by DrawingsManagerView and saved from minigames.
struct ChildDrawing: Codable, Identifiable {
    let id: String
    let name: String
    var imageUrl: String?        // R2 cloud storage URL (preferred)
    var imageData: Data?         // Legacy: base64 data (fallback)
    let uploadedAt: Date
    let source: String?          // "minigame" or "manual_upload"
    let lessonName: String?
    let lessonEmoji: String?

    init(id: String = UUID().uuidString, name: String, imageData: Data, uploadedAt: Date) {
        self.id = id
        self.name = name
        self.imageData = imageData
        self.imageUrl = nil
        self.uploadedAt = uploadedAt
        self.source = nil
        self.lessonName = nil
        self.lessonEmoji = nil
    }
    
    init(id: String = UUID().uuidString, name: String, imageUrl: String, uploadedAt: Date, source: String? = nil, lessonName: String? = nil, lessonEmoji: String? = nil) {
        self.id = id
        self.name = name
        self.imageUrl = imageUrl
        self.imageData = nil
        self.uploadedAt = uploadedAt
        self.source = source
        self.lessonName = lessonName
        self.lessonEmoji = lessonEmoji
    }
}
