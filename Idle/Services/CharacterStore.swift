import Foundation

// MARK: - StoryCharacter
struct StoryCharacter: Codable, Identifiable, Equatable {
    let id: String
    var emoji: String
    var name: String
    var description: String
    var personality: String
    /// Optional uploaded portrait (raw image bytes). Shown small in the UI.
    var imageData: Data?
    /// Hidden AI-generated one-sentence visual description of the uploaded image.
    /// Never shown to the user; folded into the story/image prompt for consistency.
    var imageDescription: String?

    init(
        id: String = UUID().uuidString,
        emoji: String,
        name: String,
        description: String,
        personality: String = "",
        imageData: Data? = nil,
        imageDescription: String? = nil
    ) {
        self.id = id
        self.emoji = emoji
        self.name = name
        self.description = description
        self.personality = personality
        self.imageData = imageData
        self.imageDescription = imageDescription
    }

    /// Prompt fragment passed to the AI. Carries all four signals so an injected
    /// character contributes name, description, personality traits, and (when an
    /// image was analyzed) the hidden one-sentence appearance.
    /// e.g. "Bearie (a fluffy bear with round cheeks; brave, gentle; small brown bear with a red scarf)"
    var promptFragment: String {
        var parts = [description]
        let traits = personality.trimmingCharacters(in: .whitespaces)
        if !traits.isEmpty { parts.append(traits) }
        let appearance = (imageDescription ?? "").trimmingCharacters(in: .whitespaces)
        if !appearance.isEmpty { parts.append(appearance) }
        return "\(name) (\(parts.joined(separator: "; ")))"
    }
}

// MARK: - CharacterStore
/// Singleton ObservableObject — persists characters to UserDefaults.
/// Shared between CharactersView (management) and StorySetupView (selection).
final class CharacterStore: ObservableObject {

    static let shared = CharacterStore()

    private let storageKey = "storydrift_characters_v1"

    @Published var characters: [StoryCharacter] {
        didSet { persist() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([StoryCharacter].self, from: data),
           !decoded.isEmpty {
            characters = decoded
        } else {
            characters = CharacterStore.defaults
        }
    }

    // MARK: - Mutations
    @discardableResult
    func add(
        emoji: String,
        name: String,
        description: String,
        personality: String,
        imageData: Data? = nil
    ) -> StoryCharacter? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let character = StoryCharacter(
            emoji: emoji,
            name: trimmed,
            description: description,
            personality: personality,
            imageData: imageData
        )
        characters.append(character)
        return character
    }

    /// Store the hidden one-sentence analysis once the background call returns.
    func setImageDescription(id: String, _ description: String) {
        guard let idx = characters.firstIndex(where: { $0.id == id }) else { return }
        characters[idx].imageDescription = description
    }

    /// Remove just the uploaded portrait (and its hidden analysis) from a character.
    func removeImage(id: String) {
        guard let idx = characters.firstIndex(where: { $0.id == id }) else { return }
        characters[idx].imageData = nil
        characters[idx].imageDescription = nil
    }

    func delete(_ character: StoryCharacter) {
        characters.removeAll { $0.id == character.id }
    }

    // MARK: - Persistence
    private func persist() {
        guard let data = try? JSONEncoder().encode(characters) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    // MARK: - Premade starter characters
    static let defaults: [StoryCharacter] = [
        StoryCharacter(emoji: "🦊", name: "Luna the fox",
                       description: "a gentle little fox with soft orange fur and a fluffy white-tipped tail",
                       personality: "curious, kind, a little shy"),
        StoryCharacter(emoji: "🐰", name: "Pip the rabbit",
                       description: "a small grey rabbit with long floppy ears and bright eyes",
                       personality: "playful, brave, cheerful"),
        StoryCharacter(emoji: "🐻", name: "Bramble the bear",
                       description: "a round brown bear who loves honey and warm hugs",
                       personality: "calm, caring, sleepy"),
    ]
}
