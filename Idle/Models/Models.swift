import Foundation

// MARK: - Child Profile
struct ChildProfile: Codable, Identifiable {
    let id: String
    let userId: String
    var name: String
    var age: Int
    var storytellingTone: StorytellingTone
    var parentPrompt: String
    var customCharacters: [CustomCharacter]
    var uploadedImages: [String]
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case userId, name, age, storytellingTone, parentPrompt
        case customCharacters, uploadedImages, createdAt, updatedAt
    }
}

struct Child: Codable, Identifiable {
    let id: String
    let userId: String
    var name: String
    var age: Int
    var storytellingTone: StorytellingTone
    var parentPrompt: String
    var customCharacters: [CustomCharacter]
    var favoriteThemes: [String]
    var initialState: InitialState
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case userId, name, age, storytellingTone, parentPrompt
        case customCharacters, favoriteThemes, initialState
        case createdAt, updatedAt
    }
}

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
struct Story: Codable, Identifiable {
    let id: String
    let childId: String
    var title: String
    var themes: [String]
    var paragraphs: [StoryParagraph]
    var images: [String]
    var scenes: [StoryScene]
    var interactiveElements: [InteractiveElement]
    var metadata: StoryMetadata
    var completed: Bool
    var sleepOnsetTime: Date?
    var duration: TimeInterval
    var driftScores: [Double]
    let generatedAt: Date
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case childId, title, themes, paragraphs, images, scenes
        case interactiveElements, metadata, completed, sleepOnsetTime
        case duration, driftScores, generatedAt, completedAt
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

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type, content, options, paragraphIndex, completed, response
    }
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

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case childId, heartRate, breathingRate, signalQuality, driftScore, timestamp
    }
}

struct VitalsSnapshot: Codable, Identifiable {
    let date: Date
    let avgHeartRate: Double
    let avgBreathingRate: Double

    var id: String { date.ISO8601Format() }
}

// MARK: - Statistics
struct ChildStatistics: Codable {
    let totalStories: Int
    let averageDuration: TimeInterval
    let averageSleepOnset: TimeInterval
    let completionRate: Double
    let vitalsHistory: [VitalsSnapshot]
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

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case email, name, picture
    }
}

// MARK: - API Request/Response Models
struct CreateChildRequest: Codable {
    var name: String
    var age: Int
    var storytellingTone: StorytellingTone
    var parentPrompt: String
    var customCharacters: [CustomCharacter]
    var favoriteThemes: [String]
    var initialState: InitialState
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
