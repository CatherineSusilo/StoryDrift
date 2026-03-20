import Foundationimport Foundation









































































































































































































}    }        case email, name, picture        case id = "_id"    enum CodingKeys: String, CodingKey {        let picture: String?    let name: String?    let email: String    let id: Stringstruct User: Codable {}    let user: User    let token: Stringstruct AuthResponse: Codable {}    let error: String?    let data: T?    let success: Boolstruct APIResponse<T: Codable>: Codable {// MARK: - API Response Types}    let avgBreathingRate: Double    let avgHeartRate: Double    let date: Date    var id: String { date.ISO8601Format() }struct VitalsSnapshot: Codable, Identifiable {}    let vitalsHistory: [VitalsSnapshot]    let completionRate: Double    let averageSleepOnset: TimeInterval    let averageDuration: TimeInterval    let totalStories: Intstruct ChildStatistics: Codable {// MARK: - Statistics}    }        case name, description, icon, isActive        case id = "_id"    enum CodingKeys: String, CodingKey {        let isActive: Bool    let icon: String    let description: String    let name: String    let id: Stringstruct StoryTheme: Codable, Identifiable {// MARK: - Story Theme}    let signalQuality: Int    let breathingRate: Double    let heartRate: Double    let timestamp: Date    let childId: Stringstruct Vitals: Codable {// MARK: - Vitals}    let breathingRate: Double?    let heartRate: Double?    let score: Double // 0-100    let timestamp: Date    var id: String { timestamp.ISO8601Format() }struct DriftScore: Codable, Identifiable {// MARK: - Drift Score}    }        case drawing        case quiz        case choice    enum InteractiveType: String, Codable {        let responseImage: String?    let userResponse: String?    let correctAnswer: String?    let options: [String]?    let prompt: String    let type: InteractiveTypestruct InteractiveElement: Codable {// MARK: - Interactive Element}    }        case text, audioUrl, interactiveElement, imageIndex        case id = "_id"    enum CodingKeys: String, CodingKey {        let imageIndex: Int?    let interactiveElement: InteractiveElement?    let audioUrl: String?    let text: String    let id: Stringstruct StoryParagraph: Codable, Identifiable {// MARK: - Story Paragraph}    }        }        case .almostThere: return "Almost There"        case .normal: return "Normal"        case .woundUp: return "Wound Up"        switch self {    var displayName: String {        case almostThere = "almost-there"    case normal    case woundUp = "wound-up"enum InitialState: String, Codable {}    }        case duration, driftScores        case sleepOnsetTime, paragraphs, images, initialState        case childId, title, themes, generatedAt, completed        case id = "_id"    enum CodingKeys: String, CodingKey {        let driftScores: [DriftScore]    let duration: TimeInterval?    let initialState: InitialState    let images: [String] // URLs to generated images    let paragraphs: [StoryParagraph]    let sleepOnsetTime: Date?    let completed: Bool    let generatedAt: Date    let themes: [String]    let title: String    let childId: String    let id: Stringstruct Story: Codable, Identifiable {// MARK: - Story}    }        case name, description, imageUrl        case id = "_id"    enum CodingKeys: String, CodingKey {        let imageUrl: String?    let description: String    let name: String    let id: Stringstruct CustomCharacter: Codable, Identifiable {// MARK: - Custom Character}    }        }        case .none: return "✨"        case .adventurous: return "🗺️"        case .sad: return "😢"        case .energetic: return "⚡"        case .calming: return "😌"        switch self {    var emoji: String {        }        }        case .none: return "None"        case .adventurous: return "Adventurous"        case .sad: return "Sad"        case .energetic: return "Energetic"        case .calming: return "Calming"        switch self {    var displayName: String {        case none    case adventurous    case sad    case energetic    case calmingenum StorytellingTone: String, Codable, CaseIterable {}    }        case uploadedImages, customCharacters, createdAt, updatedAt        case userId, name, age, storytellingTone, parentPrompt        case id = "_id"    enum CodingKeys: String, CodingKey {        let updatedAt: Date    let createdAt: Date    let customCharacters: [CustomCharacter]    let uploadedImages: [String] // URLs to uploaded images    let parentPrompt: String    let storytellingTone: StorytellingTone    let age: Int    let name: String    let userId: String    let id: Stringstruct ChildProfile: Codable, Identifiable {// MARK: - Child Profile
// MARK: - Child Profile
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
    var theme: String
    var paragraphs: [StoryParagraph]
    var scenes: [StoryScene]
    var interactiveElements: [InteractiveElement]
    var metadata: StoryMetadata
    let createdAt: Date
    let completedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case childId, title, theme, paragraphs, scenes
        case interactiveElements, metadata, createdAt, completedAt
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

// MARK: - Vitals
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

// MARK: - Statistics
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
