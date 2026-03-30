import SwiftUI
import PhotosUI

struct StorySetupView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var vitalsManager: VitalsManager
    @Binding var child: ChildProfile
    let onStartStory: (StoryConfig) -> Void
    let onBack: () -> Void

    // MARK: - ThemeStore + CharacterStore
    @StateObject private var themeStore = ThemeStore.shared
    @StateObject private var characterStore = CharacterStore.shared

    // MARK: - Form state
    @State private var selectedTheme: StoryThemeItem? = nil
    @State private var parentPrompt = ""
    @State private var storytellingTone: StorytellingTone = .calming
    @State private var initialState: InitialState = .normal
    @State private var storyLength: StoryLength = .medium
    @State private var isGenerating = false
    @State private var minigameFrequency: MinigameFrequency = .none

    // MARK: - Characters state
    @State private var selectedCharacterIds: Set<String> = []

    // MARK: - Drawings state
    @State private var savedDrawings: [ChildDrawing] = []
    @State private var selectedDrawingIds: Set<String> = []
    // Custom drawings uploaded directly in this screen (not saved to library)
    @State private var customDrawings: [CustomUpload] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false

    // MARK: - Parchment palette
    private let bg        = Color(red: 0.894, green: 0.835, blue: 0.718)
    private let cardBg    = Color(red: 0.980, green: 0.961, blue: 0.922)
    private let borderClr = Color(red: 0.157, green: 0.118, blue: 0.078).opacity(0.28)
    private let btnBg     = Color(red: 0.824, green: 0.706, blue: 0.549).opacity(0.4)
    private let ink       = Color(red: 0.078, green: 0.059, blue: 0.039)
    private let activeCardBg  = Color(red: 0.824, green: 0.706, blue: 0.549).opacity(0.45)
    private let activeBorder  = Color(red: 0.157, green: 0.118, blue: 0.078).opacity(0.65)

    enum StoryLength: String, CaseIterable {
        case short = "Short"
        case medium = "Medium"
        case long = "Long"

        var duration: Int {
            switch self {
            case .short: return 10
            case .medium: return 15
            case .long: return 20
            }
        }
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // ── Header ───────────────────────────────────────────
                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(ink)
                        }
                        Spacer()
                        Text("story setup")
                            .font(.custom("IndieFlower-Regular", size: 30))
                            .foregroundColor(ink)
                        Spacer()
                        Color.clear.frame(width: 24)
                    }
                    .padding(.top, 20)

                    // ── Theme picker ─────────────────────────────────────
                    sectionCard(title: "choose a theme") {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                            spacing: 10
                        ) {
                            ForEach(themeStore.themes) { theme in
                                themePickerCard(theme)
                            }
                        }
                    }

                    // ── Custom prompt ────────────────────────────────────
                    sectionCard(title: "or describe your own") {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $parentPrompt)
                                    .font(.custom("PatrickHand-Regular", size: 16))
                                    .foregroundColor(ink)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 80)
                                    .padding(10)
                                    .background(cardBg.opacity(0.6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(borderClr, lineWidth: 1.5)
                                    )
                                    .cornerRadius(6)

                                if parentPrompt.isEmpty {
                                    Text("tell us what \(child.name) loves — characters, places, anything special…")
                                        .font(.custom("PatrickHand-Regular", size: 16))
                                        .foregroundColor(ink.opacity(0.35))
                                        .padding(.horizontal, 14)
                                        .padding(.top, 18)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                    }

                    // ── Characters (optional) ────────────────────────────
                    if !characterStore.characters.isEmpty {
                        sectionCard(title: "add characters  ✦ optional") {
                            VStack(spacing: 8) {
                                ForEach(characterStore.characters) { character in
                                    characterPickerRow(character)
                                }
                            }
                        }
                    }

                    // ── Drawings (optional) ──────────────────────────────
                    sectionCard(title: "inspire with drawings  ✦ optional") {
                        VStack(alignment: .leading, spacing: 10) {

                            // Upload button
                            PhotosPicker(
                                selection: $pickerItems,
                                maxSelectionCount: 6,
                                matching: .images
                            ) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.up.doc")
                                        .font(.system(size: 14))
                                    Text("upload a drawing")
                                        .font(.custom("PatrickHand-Regular", size: 15))
                                        .fontWeight(.bold)
                                }
                                .foregroundColor(ink.opacity(0.8))
                                .padding(.vertical, 9)
                                .padding(.horizontal, 14)
                                .background(btnBg)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderClr, lineWidth: 1.5))
                                .cornerRadius(6)
                            }
                            .onChange(of: pickerItems) { _, _ in
                                Task { await loadPickerItems() }
                            }

                            // Custom uploads row
                            if !customDrawings.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(customDrawings) { upload in
                                            customDrawingThumbnail(upload)
                                        }
                                    }
                                }
                            }

                            // Saved library drawings (togglable)
                            if !savedDrawings.isEmpty {
                                Text("from drawing collection")
                                    .font(.custom("PatrickHand-Regular", size: 12))
                                    .foregroundColor(ink.opacity(0.45))
                                    .padding(.top, 2)

                                LazyVGrid(
                                    columns: [
                                        GridItem(.flexible(), spacing: 8),
                                        GridItem(.flexible(), spacing: 8),
                                        GridItem(.flexible(), spacing: 8)
                                    ],
                                    spacing: 8
                                ) {
                                    ForEach(savedDrawings) { drawing in
                                        drawingToggleCard(drawing)
                                    }
                                }
                            }

                            if customDrawings.isEmpty && savedDrawings.isEmpty {
                                Text("upload a photo of \(child.name)'s drawing to weave it into the story")
                                    .font(.custom("PatrickHand-Regular", size: 14))
                                    .foregroundColor(ink.opacity(0.4))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    // ── Interactive Learning Moments ─────────────────────
                    sectionCard(title: "interactive learning moments") {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                            spacing: 10
                        ) {
                            ForEach(MinigameFrequency.allCases, id: \.self) { freq in
                                minigameFrequencyCard(freq)
                            }
                        }
                    }

                    // ── Face Detection (Presage Camera) ──────────────────
                    sectionCard(title: "face detection") {
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(vitalsManager.isCameraEnabled ? "Camera On" : "Camera Off")
                                        .font(.custom("Georgia", size: 16))
                                        .fontWeight(.semibold)
                                        .foregroundColor(ink)
                                    Text(vitalsManager.isCameraEnabled ? "Tracks drift score via face detection" : "Uses synthetic drift score")
                                        .font(.custom("Georgia", size: 13))
                                        .foregroundColor(ink.opacity(0.7))
                                }
                                Spacer()
                                Toggle("", isOn: $vitalsManager.isCameraEnabled)
                                    .labelsHidden()
                                    .tint(Color(red: 0.824, green: 0.706, blue: 0.549))
                            }
                            
                            if !vitalsManager.isCameraEnabled {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(ink.opacity(0.5))
                                    Text("Drift score will increase steadily from 0→100 over the story duration")
                                        .font(.custom("Georgia", size: 12))
                                        .foregroundColor(ink.opacity(0.6))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.top, 4)
                            }
                        }
                    }

                    // ── Story Length ─────────────────────────────────────
                    sectionCard(title: "story length") {
                        HStack(spacing: 10) {
                            ForEach(StoryLength.allCases, id: \.self) { len in
                                Button {
                                    storyLength = len
                                } label: {
                                    VStack(spacing: 3) {
                                        Text(len.rawValue.lowercased())
                                            .font(.custom("PatrickHand-Regular", size: 16))
                                            .fontWeight(storyLength == len ? .bold : .regular)
                                        Text("\(len.duration) min")
                                            .font(.custom("PatrickHand-Regular", size: 12))
                                            .opacity(0.65)
                                    }
                                    .foregroundColor(ink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(storyLength == len ? activeCardBg : cardBg.opacity(0.5))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(storyLength == len ? activeBorder : borderClr, lineWidth: storyLength == len ? 2 : 1)
                                    )
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }

                    // ── Storytelling Tone ────────────────────────────────
                    sectionCard(title: "storytelling tone") {
                        VStack(spacing: 8) {
                            ForEach(StorytellingTone.allCases, id: \.self) { tone in
                                toneRow(tone)
                            }
                        }
                    }

                    // ── Child's Current State ────────────────────────────
                    sectionCard(title: "child's current state") {
                        VStack(spacing: 8) {
                            ForEach(InitialState.allCases, id: \.self) { state in
                                stateRow(state)
                            }
                        }
                    }

                    // ── Start button ─────────────────────────────────────
                    Button(action: handleStartStory) {
                        HStack(spacing: 10) {
                            if isGenerating {
                                ProgressView().tint(ink)
                            } else {
                                Image(systemName: "moon.stars.fill")
                                    .font(.system(size: 20))
                            }
                            Text(isGenerating ? "generating story…" : "begin the story")
                                .font(.custom("IndieFlower-Regular", size: 22))
                                .fontWeight(.bold)
                        }
                        .foregroundColor(ink.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(btnBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(activeBorder, lineWidth: 2)
                        )
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                    .disabled(isGenerating || (selectedTheme == nil && parentPrompt.trimmingCharacters(in: .whitespaces).isEmpty))
                    .opacity((selectedTheme == nil && parentPrompt.trimmingCharacters(in: .whitespaces).isEmpty) ? 0.5 : 1)

                    // ── DEBUG ────────────────────────────────────────────
                    #if DEBUG
                    Button(action: handleStartStoryDebug) {
                        HStack(spacing: 8) {
                            Image(systemName: "stopwatch")
                            VStack(spacing: 1) {
                                Text("2-min test story")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("same settings · 4 paragraphs · all features enabled")
                                    .font(.system(size: 11))
                                    .opacity(0.7)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.4), lineWidth: 1.5))
                    }
                    .disabled(isGenerating)
                    #endif

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationBarHidden(true)
        .onAppear { loadDrawings() }
        .onChange(of: selectedTheme) { _, theme in
            if let theme, parentPrompt.isEmpty {
                parentPrompt = theme.name
            }
        }
    }

    // MARK: - Section card wrapper
    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.custom("PatrickHand-Regular", size: 14))
                .foregroundColor(ink.opacity(0.55))
                .textCase(.uppercase)
                .kerning(1.2)
            content()
        }
        .padding(16)
        .background(cardBg.opacity(0.7))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(borderClr, lineWidth: 1.5))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 2)
    }

    // MARK: - Theme picker card
    @ViewBuilder
    private func themePickerCard(_ theme: StoryThemeItem) -> some View {
        let isActive = selectedTheme?.id == theme.id
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedTheme = isActive ? nil : theme
                if !isActive {
                    // Reflect theme in prompt when nothing else typed yet
                    if parentPrompt.isEmpty { parentPrompt = theme.name }
                } else {
                    if parentPrompt == theme.name { parentPrompt = "" }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(theme.icon).font(.system(size: 26))
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.name)
                        .font(.custom("PatrickHand-Regular", size: 15))
                        .fontWeight(isActive ? .bold : .regular)
                        .foregroundColor(ink)
                    Text(theme.description)
                        .font(.custom("PatrickHand-Regular", size: 12))
                        .foregroundColor(ink.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ink.opacity(0.7))
                }
            }
            .padding(10)
            .background(isActive ? activeCardBg : cardBg.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? activeBorder : borderClr, lineWidth: isActive ? 2 : 1)
            )
            .cornerRadius(6)
        }
    }

    // MARK: - Drawing toggle card
    @ViewBuilder
    private func drawingToggleCard(_ drawing: ChildDrawing) -> some View {
        let isSelected = selectedDrawingIds.contains(drawing.id)
        Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                if isSelected { selectedDrawingIds.remove(drawing.id) }
                else { selectedDrawingIds.insert(drawing.id) }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 4) {
                    if let uiImage = UIImage(data: drawing.imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 80)
                            .clipped()
                            .cornerRadius(4)
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(cardBg)
                            .frame(height: 80)
                            .overlay(Image(systemName: "photo").foregroundColor(ink.opacity(0.3)))
                    }
                    Text(drawing.name)
                        .font(.custom("PatrickHand-Regular", size: 11))
                        .foregroundColor(ink.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(6)
                .background(isSelected ? activeCardBg : cardBg.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? activeBorder : borderClr, lineWidth: isSelected ? 2 : 1)
                )
                .cornerRadius(6)

                // Checkmark badge
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(ink.opacity(0.75))
                        .padding(4)
                }
            }
        }
    }

    // MARK: - Character picker row
    @ViewBuilder
    private func characterPickerRow(_ character: StoryCharacter) -> some View {
        let isActive = selectedCharacterIds.contains(character.id)
        Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                if isActive { selectedCharacterIds.remove(character.id) }
                else { selectedCharacterIds.insert(character.id) }
            }
        } label: {
            HStack(spacing: 12) {
                Text(character.emoji)
                    .font(.system(size: 24))
                    .frame(width: 36, height: 36)
                    .background(isActive ? activeCardBg : bg.opacity(0.5))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(isActive ? activeBorder : borderClr, lineWidth: isActive ? 1.5 : 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(character.name)
                        .font(.custom("PatrickHand-Regular", size: 15))
                        .fontWeight(isActive ? .bold : .regular)
                        .foregroundColor(ink)
                    if !character.description.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(character.description)
                            .font(.custom("PatrickHand-Regular", size: 12))
                            .foregroundColor(ink.opacity(0.55))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ink.opacity(0.7))
                }
            }
            .padding(10)
            .background(isActive ? activeCardBg : cardBg.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? activeBorder : borderClr, lineWidth: isActive ? 2 : 1)
            )
            .cornerRadius(6)
        }
    }

    // MARK: - Tone row
    @ViewBuilder
    private func toneRow(_ tone: StorytellingTone) -> some View {
        let isActive = storytellingTone == tone
        Button { storytellingTone = tone } label: {
            HStack(spacing: 12) {
                Text(tone.emoji).font(.system(size: 22))
                Text(tone.displayName)
                    .font(.custom("PatrickHand-Regular", size: 16))
                    .fontWeight(isActive ? .bold : .regular)
                    .foregroundColor(ink)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(ink.opacity(0.65))
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(isActive ? activeCardBg : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? activeBorder : borderClr.opacity(0.4), lineWidth: isActive ? 1.5 : 1)
            )
            .cornerRadius(6)
        }
    }

    // MARK: - State row
    @ViewBuilder
    private func stateRow(_ state: InitialState) -> some View {
        let isActive = initialState == state
        Button { initialState = state } label: {
            HStack {
                Text(state.displayName)
                    .font(.custom("PatrickHand-Regular", size: 16))
                    .fontWeight(isActive ? .bold : .regular)
                    .foregroundColor(ink)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(ink.opacity(0.65))
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(isActive ? activeCardBg : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? activeBorder : borderClr.opacity(0.4), lineWidth: isActive ? 1.5 : 1)
            )
            .cornerRadius(6)
        }
    }

    // MARK: - Minigame frequency card
    @ViewBuilder
    private func minigameFrequencyCard(_ freq: MinigameFrequency) -> some View {
        let isActive = minigameFrequency == freq
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                minigameFrequency = freq
            }
        } label: {
            VStack(spacing: 10) {
                if freq.usesSFSymbol {
                    Image(systemName: freq.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(ink.opacity(0.55))
                        .frame(height: 30)
                } else {
                    Text(freq.icon)
                        .font(.system(size: 26))
                        .frame(height: 30)
                }
                Text(freq.displayName)
                    .font(.custom("PatrickHand-Regular", size: 14))
                    .foregroundColor(ink.opacity(isActive ? 1.0 : 0.7))
                    .fontWeight(isActive ? .bold : .regular)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isActive ? activeCardBg : cardBg.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? activeBorder : borderClr, lineWidth: isActive ? 2 : 1)
            )
            .cornerRadius(8)
        }
    }

    // MARK: - Custom drawing thumbnail (with remove button)
    @ViewBuilder
    private func customDrawingThumbnail(_ upload: CustomUpload) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: upload.image)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .clipped()
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(activeBorder, lineWidth: 2))

            // Remove button
            Button {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    customDrawings.removeAll { $0.id == upload.id }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color(red: 0.4, green: 0.25, blue: 0.15).opacity(0.85))
                    .clipShape(Circle())
            }
            .padding(3)
        }
    }

    // MARK: - Load PhotosPicker items into CustomUpload array
    private func loadPickerItems() async {
        var loaded: [CustomUpload] = []
        for item in pickerItems {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: data) else { continue }
            loaded.append(CustomUpload(image: img, data: data))
        }
        await MainActor.run {
            // Append without duplicating already-loaded ones
            let existingData = Set(customDrawings.map { $0.data })
            customDrawings.append(contentsOf: loaded.filter { !existingData.contains($0.data) })
            pickerItems = []
        }
    }

    // MARK: - Load child's saved drawings from UserDefaults
    private func loadDrawings() {
        let key = "drawings_\(child.id)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ChildDrawing].self, from: data) else {
            savedDrawings = []
            return
        }
        savedDrawings = decoded
    }

    // MARK: - Build base64 strings for chosen drawings
    private func selectedDrawingBase64() -> [String] {
        let fromLibrary = savedDrawings
            .filter { selectedDrawingIds.contains($0.id) }
            .map { $0.imageData.base64EncodedString() }
        let fromCustom = customDrawings.map { $0.data.base64EncodedString() }
        return fromLibrary + fromCustom
    }

    // MARK: - Build character prompt fragments for chosen characters
    private func selectedCharacterPrompts() -> [String] {
        characterStore.characters
            .filter { selectedCharacterIds.contains($0.id) }
            .map { $0.promptFragment }
    }

    // MARK: - Start story
    private func handleStartStory() {
        isGenerating = true
        let prompt = parentPrompt.trimmingCharacters(in: .whitespaces).isEmpty
            ? (selectedTheme?.name ?? "a magical bedtime adventure")
            : parentPrompt

        var config = StoryConfig(
            childId: child.id,
            name: child.name,
            age: child.age,
            storytellingTone: storytellingTone.rawValue,
            parentPrompt: prompt,
            initialState: initialState.rawValue
        )
        let drawings = selectedDrawingBase64()
        if !drawings.isEmpty { config.drawingPrompts = drawings }
        let chars = selectedCharacterPrompts()
        if !chars.isEmpty { config.characters = chars }
        if minigameFrequency != .none { config.minigameFrequency = minigameFrequency.rawValue }
        config.targetDuration = storyLength.duration
        config.cameraEnabled = vitalsManager.isCameraEnabled

        isGenerating = false
        onStartStory(config)
    }

    // MARK: - DEBUG
    #if DEBUG
    private func handleStartStoryDebug() {
        isGenerating = true
        let prompt = parentPrompt.trimmingCharacters(in: .whitespaces).isEmpty
            ? (selectedTheme?.name ?? "a magical bedtime adventure")
            : parentPrompt

        // Identical to handleStartStory but targetDuration = 2 (→ 4 paragraphs, ~2 min)
        var config = StoryConfig(
            childId: child.id,
            name: child.name,
            age: child.age,
            storytellingTone: storytellingTone.rawValue,
            parentPrompt: prompt,
            initialState: initialState.rawValue
        )
        let drawings = selectedDrawingBase64()
        if !drawings.isEmpty { config.drawingPrompts = drawings }
        let chars = selectedCharacterPrompts()
        if !chars.isEmpty { config.characters = chars }
        if minigameFrequency != .none { config.minigameFrequency = minigameFrequency.rawValue }
        config.targetDuration = 2          // 2-minute test run
        config.cameraEnabled = vitalsManager.isCameraEnabled
        isGenerating = false
        onStartStory(config)
    }
    #endif
}

// MARK: - CustomUpload  (transient — not persisted to library)
private struct CustomUpload: Identifiable {
    let id = UUID()
    let image: UIImage
    let data: Data
}

// MARK: - Preview
#Preview {
    StorySetupView(
        child: .constant(Child(
            id: "1", userId: "user1", name: "Emma", age: 5,
            dateOfBirth: nil, avatar: nil,
            createdAt: Date(), updatedAt: Date(), preferences: nil
        )),
        onStartStory: { _ in },
        onBack: {}
    )
    .environmentObject(AuthManager())
}
