import SwiftUI

struct StoryThemesView: View {
    @State private var selectedCategory: ThemeCategory = .all
    @State private var searchText = ""
    
    let onThemeSelect: (String) -> Void
    
    private let themeCategories: [ThemeCategory: [StoryTheme]] = [
        .adventure: [
            StoryTheme(emoji: "🏰", name: "Castle Adventure", description: "Knights and dragons"),
            StoryTheme(emoji: "🗺️", name: "Treasure Hunt", description: "Maps and exploration"),
            StoryTheme(emoji: "🚀", name: "Space Explorer", description: "Galactic adventures"),
            StoryTheme(emoji: "🏴‍☠️", name: "Pirate Journey", description: "Sailing the seas"),
            StoryTheme(emoji: "🦖", name: "Dinosaur Discovery", description: "Prehistoric world")
        ],
        .nature: [
            StoryTheme(emoji: "🌲", name: "Magic Forest", description: "Enchanted woods"),
            StoryTheme(emoji: "🌊", name: "Ocean Depths", description: "Underwater world"),
            StoryTheme(emoji: "🏔️", name: "Mountain Quest", description: "Snowy peaks"),
            StoryTheme(emoji: "🌈", name: "Rainbow Valley", description: "Colorful meadows"),
            StoryTheme(emoji: "🌙", name: "Moonlit Garden", description: "Nighttime magic")
        ],
        .fantasy: [
            StoryTheme(emoji: "🧙‍♀️", name: "Wizard School", description: "Magic and spells"),
            StoryTheme(emoji: "🦄", name: "Unicorn Kingdom", description: "Mythical creatures"),
            StoryTheme(emoji: "🐉", name: "Dragon Friends", description: "Friendly dragons"),
            StoryTheme(emoji: "✨", name: "Fairy Tales", description: "Classic stories"),
            StoryTheme(emoji: "🔮", name: "Crystal Cave", description: "Magical gems")
        ],
        .educational: [
            StoryTheme(emoji: "🔬", name: "Science Lab", description: "Experiments"),
            StoryTheme(emoji: "📚", name: "Library Mystery", description: "Books and learning"),
            StoryTheme(emoji: "🌍", name: "World Traveler", description: "Geography"),
            StoryTheme(emoji: "⚗️", name: "Alchemy", description: "Mixing potions"),
            StoryTheme(emoji: "🎨", name: "Art Studio", description: "Creativity")
        ],
        .cozy: [
            StoryTheme(emoji: "☕", name: "Cozy Cafe", description: "Warm drinks"),
            StoryTheme(emoji: "🏡", name: "Home Sweet Home", description: "Family stories"),
            StoryTheme(emoji: "🐻", name: "Teddy Bear Picnic", description: "Stuffed friends"),
            StoryTheme(emoji: "⛺", name: "Camping Night", description: "Under the stars"),
            StoryTheme(emoji: "🎵", name: "Music Box", description: "Lullabies")
        ]
    ]
    
    private var filteredThemes: [(ThemeCategory, [StoryTheme])] {
        let themes = selectedCategory == .all
            ? Array(themeCategories)
            : [(selectedCategory, themeCategories[selectedCategory] ?? [])]
        
        if searchText.isEmpty {
            return themes
        }
        
        return themes.compactMap { category, themeList in
            let filtered = themeList.filter { theme in
                theme.name.localizedCaseInsensitiveContains(searchText) ||
                theme.description.localizedCaseInsensitiveContains(searchText)
            }
            return filtered.isEmpty ? nil : (category, filtered)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                Text("Choose a Theme")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.5))
                    
                    TextField("Search themes...", text: $searchText)
                        .foregroundColor(.white)
                        .accentColor(.purple)
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                
                // Category pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(ThemeCategory.allCases, id: \.self) { category in
                            CategoryPill(
                                category: category,
                                isSelected: selectedCategory == category,
                                onTap: { selectedCategory = category }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding()
            .background(Color.black.opacity(0.3))
            
            // Themes Grid
            ScrollView {
                LazyVStack(spacing: 24) {
                    ForEach(filteredThemes, id: \.0) { category, themes in
                        VStack(alignment: .leading, spacing: 16) {
                            if selectedCategory == .all {
                                Text(category.displayName)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal)
                            }
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 16) {
                                ForEach(themes) { theme in
                                    ThemeCard(theme: theme, onSelect: {
                                        onThemeSelect(theme.name)
                                    })
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.15, green: 0.05, blue: 0.25)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

struct StoryTheme: Identifiable {
    let id = UUID()
    let emoji: String
    let name: String
    let description: String
}

enum ThemeCategory: String, CaseIterable {
    case all = "All"
    case adventure = "Adventure"
    case nature = "Nature"
    case fantasy = "Fantasy"
    case educational = "Educational"
    case cozy = "Cozy"
    
    var displayName: String {
        rawValue
    }
    
    var icon: String {
        switch self {
        case .all: return "star.fill"
        case .adventure: return "map.fill"
        case .nature: return "leaf.fill"
        case .fantasy: return "sparkles"
        case .educational: return "book.fill"
        case .cozy: return "heart.fill"
        }
    }
}

struct CategoryPill: View {
    let category: ThemeCategory
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 14))
                
                Text(category.displayName)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(isSelected ? Color(red: 0.05, green: 0.05, blue: 0.15) : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white : Color.white.opacity(0.1))
            )
        }
    }
}

struct ThemeCard: View {
    let theme: StoryTheme
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                Text(theme.emoji)
                    .font(.system(size: 48))
                
                Text(theme.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(theme.description)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

#Preview {
    StoryThemesView { theme in
        print("Selected: \(theme)")
    }
}
