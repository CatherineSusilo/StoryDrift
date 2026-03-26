import Foundation

// MARK: - StoryCharacter
struct StoryCharacter: Codable, Identifiable, Equatable {
    let id: String
    var emoji: String
    var name: String
    var description: String
    var personality: String

    init(
        id: String = UUID().uuidString,
        emoji: String,
        name: String,
        description: String,
        personality: String = ""
    ) {
        self.id = id
        self.emoji = emoji
        self.name = name
        self.description = description
        self.personality = personality
    }

    /// Short prompt fragment passed to the AI (e.g. "Bearie (a fluffy bear with round cheeks; brave, gentle)")
    var promptFragment: String {
        var parts = [description]
        if !personality.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(personality)
        }
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
            characters = []
        }
    }

    // MARK: - Mutations
    func add(emoji: String, name: String, description: String, personality: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        characters.append(StoryCharacter(
            emoji: emoji,
            name: trimmed,
            description: description,
            personality: personality
        ))
    }

    func delete(_ character: StoryCharacter) {
        characters.removeAll { $0.id == character.id }
    }

    // MARK: - Persistence
    private func persist() {
        guard let data = try? JSONEncoder().encode(characters) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
