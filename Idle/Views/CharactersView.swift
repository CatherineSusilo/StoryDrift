import SwiftUI

// MARK: - CharactersView
struct CharactersView: View {

    @StateObject private var store = CharacterStore.shared

    // form state
    @State private var showForm = false
    @State private var newEmoji = "👾"
    @State private var newName = ""
    @State private var newDescription = ""
    @State private var newPersonality = ""

    // expanded character card ids
    @State private var expandedIds: Set<String> = []

    // parchment palette
    private let bg        = Color(red: 0.894, green: 0.835, blue: 0.718)
    private let cardBg    = Color(red: 0.980, green: 0.961, blue: 0.922)
    private let borderClr = Color(red: 0.157, green: 0.118, blue: 0.078).opacity(0.28)
    private let btnBg     = Color(red: 0.824, green: 0.706, blue: 0.549).opacity(0.4)
    private let ink       = Color(red: 0.078, green: 0.059, blue: 0.039)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ── Header ───────────────────────────────────────────
                    HStack(alignment: .center) {
                        Text("characters")
                            .font(.custom("IndieFlower-Regular", size: 34))
                            .foregroundColor(ink)

                        Spacer()

                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showForm.toggle()
                                if !showForm { clearForm() }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: showForm ? "minus" : "plus")
                                    .font(.system(size: 13, weight: .bold))
                                Text("new character")
                                    .font(.custom("PatrickHand-Regular", size: 16))
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

                    // ── Create form ──────────────────────────────────────
                    if showForm {
                        createFormCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // ── Character list ───────────────────────────────────
                    if store.characters.isEmpty && !showForm {
                        emptyState
                    } else {
                        ForEach(store.characters) { character in
                            characterCard(character)
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Create form card
    private var createFormCard: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Emoji + Name row
            HStack(spacing: 12) {
                // Emoji field
                TextField("👾", text: $newEmoji)
                    .font(.system(size: 28))
                    .multilineTextAlignment(.center)
                    .frame(width: 80)
                    .padding(.vertical, 12)
                    .background(cardBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(borderClr, lineWidth: 1.5)
                    )
                    .cornerRadius(6)

                // Name field
                parchmentField("character name", text: $newName)
            }

            // Description field
            parchmentMultiline(
                "description (who is this character? what do they look like?)",
                text: $newDescription
            )

            // Personality field
            parchmentMultiline(
                "personality traits (brave, gentle, curious, funny…)",
                text: $newPersonality
            )

            // Create button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    store.add(
                        emoji: newEmoji.trimmingCharacters(in: .whitespaces).isEmpty ? "👾" : newEmoji,
                        name: newName,
                        description: newDescription,
                        personality: newPersonality
                    )
                    clearForm()
                    showForm = false
                }
            } label: {
                Text("create character")
                    .font(.custom("PatrickHand-Regular", size: 16))
                    .fontWeight(.bold)
                    .foregroundColor(ink.opacity(0.85))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .background(btnBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(borderClr, lineWidth: 1.5)
                    )
                    .cornerRadius(6)
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(newName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .padding(16)
        .background(cardBg.opacity(0.9))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderClr, lineWidth: 1.5)
        )
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    // MARK: - Character list card
    @ViewBuilder
    private func characterCard(_ character: StoryCharacter) -> some View {
        let isExpanded = expandedIds.contains(character.id)

        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 14) {
                // Emoji avatar circle
                Text(character.emoji)
                    .font(.system(size: 30))
                    .frame(width: 48, height: 48)
                    .background(bg.opacity(0.6))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(borderClr, lineWidth: 1))

                // Name + description
                VStack(alignment: .leading, spacing: 3) {
                    Text(character.name)
                        .font(.custom("IndieFlower-Regular", size: 22))
                        .foregroundColor(ink)
                    if !character.description.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(character.description)
                            .font(.custom("PatrickHand-Regular", size: 14))
                            .foregroundColor(ink.opacity(0.6))
                            .lineLimit(isExpanded ? nil : 1)
                    }
                }

                Spacer()

                // Story count badge
                Text("0 stories")
                    .font(.custom("PatrickHand-Regular", size: 12))
                    .foregroundColor(ink.opacity(0.55))
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(bg.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(borderClr, lineWidth: 1)
                    )
                    .cornerRadius(4)

                // Expand chevron
                if !character.personality.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            if isExpanded { expandedIds.remove(character.id) }
                            else { expandedIds.insert(character.id) }
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(ink.opacity(0.5))
                            .frame(width: 28, height: 28)
                    }
                }
            }
            .padding(16)

            // Expanded personality row
            if isExpanded && !character.personality.trimmingCharacters(in: .whitespaces).isEmpty {
                Divider()
                    .background(borderClr)
                    .padding(.horizontal, 16)

                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundColor(ink.opacity(0.4))
                    Text(character.personality)
                        .font(.custom("PatrickHand-Regular", size: 14))
                        .foregroundColor(ink.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(cardBg.opacity(0.85))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderClr, lineWidth: 1.5)
        )
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation { store.delete(character) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty state
    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("🧸")
                .font(.system(size: 48))
            Text("no characters yet")
                .font(.custom("PatrickHand-Regular", size: 18))
                .foregroundColor(ink.opacity(0.5))
            Text("create a character to add them to your stories")
                .font(.custom("PatrickHand-Regular", size: 14))
                .foregroundColor(ink.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(cardBg.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderClr, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
        .cornerRadius(10)
    }

    // MARK: - Parchment text field helper
    @ViewBuilder
    private func parchmentField(_ placeholder: String, text: Binding<String>) -> some View {
        ZStack(alignment: .leading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.custom("PatrickHand-Regular", size: 16))
                    .foregroundColor(ink.opacity(0.35))
                    .padding(.horizontal, 12)
                    .allowsHitTesting(false)
            }
            TextField("", text: text)
                .font(.custom("PatrickHand-Regular", size: 16))
                .foregroundColor(ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
        }
        .background(cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderClr, lineWidth: 1.5)
        )
        .cornerRadius(6)
    }

    // MARK: - Parchment multiline field helper
    @ViewBuilder
    private func parchmentMultiline(_ placeholder: String, text: Binding<String>) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.custom("PatrickHand-Regular", size: 15))
                    .foregroundColor(ink.opacity(0.35))
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .allowsHitTesting(false)
            }
            TextEditor(text: text)
                .font(.custom("PatrickHand-Regular", size: 15))
                .foregroundColor(ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .background(cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderClr, lineWidth: 1.5)
        )
        .cornerRadius(6)
    }

    // MARK: - Helpers
    private func clearForm() {
        newEmoji = "👾"
        newName = ""
        newDescription = ""
        newPersonality = ""
    }
}

#Preview {
    CharactersView()
}
