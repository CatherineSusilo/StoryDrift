import SwiftUI

// MARK: - StoryThemesView  (ported from StoryThemes.tsx)
struct StoryThemesView: View {

    // MARK: - State
    @StateObject private var store = ThemeStore.shared
    @State private var showAddForm = false
    @State private var newName = ""
    @State private var newDescription = ""
    @State private var newIcon = "📖"

    // MARK: - Parchment palette  (matches DrawingsManagerView + StoryThemes.tsx)
    private let bg        = Color(red: 0.894, green: 0.835, blue: 0.718)
    private let cardBg    = Color(red: 0.980, green: 0.961, blue: 0.922)
    private let borderClr = Color(red: 0.157, green: 0.118, blue: 0.078).opacity(0.28)
    private let btnBg     = Color(red: 0.824, green: 0.706, blue: 0.549).opacity(0.4)
    private let ink       = Color(red: 0.078, green: 0.059, blue: 0.039)

    // MARK: - Body
    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Header ──────────────────────────────────────────
                    HStack {
                        Text("story themes")
                            .font(.custom("IndieFlower-Regular", size: 34))
                            .foregroundColor(ink)

                        Spacer()

                        // "add theme" button
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showAddForm.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: showAddForm ? "minus" : "plus")
                                    .font(.system(size: 14, weight: .bold))
                                Text("add theme")
                                    .font(.custom("PatrickHand-Regular", size: 17))
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(ink.opacity(0.85))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(btnBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(borderClr, lineWidth: 2)
                            )
                            .cornerRadius(6)
                            .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
                        }
                    }
                    .padding(.top, 20)

                    // ── Add Theme Form ───────────────────────────────────
                    if showAddForm {
                        addThemeForm
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // ── Themes Grid ──────────────────────────────────────
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 14
                    ) {
                        ForEach(store.themes) { theme in
                            themeCard(theme)
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Add Theme Form
    private var addThemeForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                // Emoji / icon field
                TextField("emoji", text: $newIcon)
                    .font(.custom("PatrickHand-Regular", size: 22))
                    .foregroundColor(ink)
                    .multilineTextAlignment(.center)
                    .frame(width: 64)
                    .padding(10)
                    .background(cardBg.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(borderClr, lineWidth: 1.5)
                    )
                    .cornerRadius(6)

                VStack(spacing: 8) {
                    // Theme name
                    TextField("theme name", text: $newName)
                        .font(.custom("PatrickHand-Regular", size: 17))
                        .foregroundColor(ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(cardBg.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(borderClr, lineWidth: 1.5)
                        )
                        .cornerRadius(6)

                    // Short description
                    TextField("short description", text: $newDescription)
                        .font(.custom("PatrickHand-Regular", size: 17))
                        .foregroundColor(ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(cardBg.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(borderClr, lineWidth: 1.5)
                        )
                        .cornerRadius(6)
                }
            }

            // Save button
            Button {
                saveTheme()
            } label: {
                Text("save theme")
                    .font(.custom("PatrickHand-Regular", size: 17))
                    .fontWeight(.bold)
                    .foregroundColor(ink.opacity(0.85))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .background(btnBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(borderClr, lineWidth: 2)
                    )
                    .cornerRadius(6)
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(16)
        .background(cardBg.opacity(0.9))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderClr, lineWidth: 2)
        )
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    // MARK: - Theme Card
    @ViewBuilder
    private func themeCard(_ theme: StoryThemeItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(theme.icon)
                .font(.system(size: 38))

            Text(theme.name)
                .font(.custom("IndieFlower-Regular", size: 20))
                .fontWeight(.bold)
                .foregroundColor(ink)

            Text(theme.description)
                .font(.custom("PatrickHand-Regular", size: 14))
                .foregroundColor(ink.opacity(0.65))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBg.opacity(0.85))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderClr, lineWidth: 2)
        )
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 2)
    }

    // MARK: - Actions
    private func saveTheme() {
        store.add(icon: newIcon,
                  name: newName,
                  description: newDescription)
        newName = ""
        newDescription = ""
        newIcon = "📖"
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showAddForm = false
        }
    }
}

// MARK: - Preview
#Preview {
    StoryThemesView()
}
