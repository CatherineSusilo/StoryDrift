import Foundation
import Combine

// MARK: - StoryThemeItem
/// Persisted theme model — shared between StoryThemesView (management) and StorySetupView (selection).
struct StoryThemeItem: Codable, Identifiable, Equatable {
    let id: String
    var icon: String
    var name: String
    var description: String

    init(id: String = UUID().uuidString, icon: String, name: String, description: String) {
        self.id = id
        self.icon = icon
        self.name = name
        self.description = description
    }
}

// MARK: - ThemeStore
/// Singleton ObservableObject — keeps the theme list in UserDefaults so that
/// changes made in StoryThemesView are immediately visible in StorySetupView.
final class ThemeStore: ObservableObject {

    static let shared = ThemeStore()

    private let storageKey = "storydrift_themes_v1"

    @Published var themes: [StoryThemeItem] {
        didSet { persist() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([StoryThemeItem].self, from: data),
           !decoded.isEmpty {
            themes = decoded
        } else {
            themes = ThemeStore.defaults
        }
    }

    // MARK: - Mutations
    func add(icon: String, name: String, description: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        themes.append(StoryThemeItem(icon: icon, name: trimmed, description: description))
    }

    func delete(_ item: StoryThemeItem) {
        themes.removeAll { $0.id == item.id }
    }

    // MARK: - Persistence
    private func persist() {
        guard let data = try? JSONEncoder().encode(themes) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    // MARK: - Defaults  (from StoryThemes.tsx)
    static let defaults: [StoryThemeItem] = [
        StoryThemeItem(icon: "🌲", name: "enchanted forest",  description: "magical creatures and hidden paths"),
        StoryThemeItem(icon: "🌊", name: "ocean adventure",   description: "underwater worlds and friendly sea life"),
        StoryThemeItem(icon: "✨", name: "space explorer",    description: "stars, planets, and cosmic journeys"),
        StoryThemeItem(icon: "🏡", name: "cozy village",      description: "warm homes and kind neighbors"),
        StoryThemeItem(icon: "🐉", name: "friendly dragons",  description: "gentle dragons and castle tales"),
        StoryThemeItem(icon: "🎪", name: "bedtime circus",    description: "soft acrobats and sleepy performers"),
    ]
}
