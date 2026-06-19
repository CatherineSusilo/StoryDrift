import SwiftUI

// MARK: - BedtimeStorySessionView
//
// Bedtime story setup + playback wrapper.
// Setup form → pregenerate story via /api/generate/story → hand off to StoryPlaybackView.
// Drift tracking, audio chaining, image polling, and fade-to-black are handled by
// StoryPlaybackView itself (which already supports the pregen flow).

struct BedtimeStorySessionView: View {
    let child: ChildProfile
    let onComplete: ([Double], TimeInterval) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var eyeTracking: EyeTrackingManager

    @State private var phase: BedtimePhase = .setup

    // Setup form
    @State private var favoriteAnimal = ""
    @State private var favoritePlace  = ""
    @State private var selectedMood: TonightsMood = .normal

    @State private var generatedStory: Story? = nil
    @State private var errorMessage: String? = nil

    enum BedtimePhase { case setup, loading, playing }
    enum TonightsMood: String, CaseIterable {
        case wound_up     = "wound-up"
        case normal       = "normal"
        case almost_there = "almost-there"

        var label: String {
            switch self {
            case .wound_up:     return "Wound Up 🌪️"
            case .normal:       return "Normal 😊"
            case .almost_there: return "Almost There 😴"
            }
        }
    }

    var body: some View {
        ZStack {
            switch phase {
            case .setup:                                setupView
            case .loading:                              loadingView
            case .playing:
                if let story = generatedStory {
                    StoryPlaybackView(story: story, mode: .bedtime) { drift, duration, _ in
                        Task { await finalize(story: story, drift: drift, duration: duration) }
                    }
                    .environmentObject(authManager)
                    .environmentObject(eyeTracking)
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: phase)
    }

    // MARK: - Setup view

    private var setupView: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("🌙 Bedtime Story")
                            .font(Theme.titleFont(size: 28))
                            .foregroundColor(Theme.ink)
                        Text("for \(child.name)")
                            .font(Theme.bodyFont(size: 17))
                            .foregroundColor(Theme.inkMuted)
                    }
                    .padding(.top, 20)

                    formField(icon: "pawprint.fill", label: "Favourite animal",
                              placeholder: "e.g. fox, rabbit, elephant", text: $favoriteAnimal)
                    formField(icon: "map.fill",       label: "Favourite place",
                              placeholder: "e.g. enchanted forest, moon, cosy cottage", text: $favoritePlace)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("How are they feeling tonight?", systemImage: "moon.stars.fill")
                            .font(Theme.bodyFont(size: 15))
                            .foregroundColor(Theme.inkMuted)
                        HStack(spacing: 10) {
                            ForEach(TonightsMood.allCases, id: \.self) { mood in
                                moodButton(mood)
                            }
                        }
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(Theme.bodyFont(size: 13))
                            .foregroundColor(.red)
                    }

                    Spacer(minLength: 16)

                    Button {
                        Task { await startGeneration() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "moon.zzz.fill")
                            Text("Begin Story").fontWeight(.semibold)
                        }
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(colors: [Color.indigo, Color.purple],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    private func formField(icon: String, label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(Theme.bodyFont(size: 15))
                .foregroundColor(Theme.inkMuted)
            TextField(placeholder, text: text)
                .font(Theme.bodyFont(size: 16))
                .foregroundColor(Theme.ink)
                .padding(12)
                .background(Theme.card)
                .cornerRadius(Theme.radiusMD)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMD)
                        .stroke(Theme.border, lineWidth: 1)
                )
        }
    }

    private func moodButton(_ mood: TonightsMood) -> some View {
        let selected = selectedMood == mood
        return Button {
            withAnimation(.spring(response: 0.3)) { selectedMood = mood }
        } label: {
            Text(mood.label)
                .font(Theme.bodyFont(size: 13))
                .foregroundColor(selected ? .white : Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(selected ? Color.indigo : Theme.card)
                .cornerRadius(Theme.radiusSM)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSM)
                        .stroke(selected ? Color.indigo : Theme.border, lineWidth: 1.5)
                )
        }
    }

    // MARK: - Loading view

    private var loadingView: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.04, green: 0.04, blue: 0.12),
                                     Color(red: 0.08, green: 0.04, blue: 0.18)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Text("🌙").font(.system(size: 60))
                ProgressView().tint(.white).scaleEffect(1.4)
                Text("Setting the scene…")
                    .font(.custom("Georgia", size: 18))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }

    // MARK: - Story generation

    private func startGeneration() async {
        guard let token = authManager.accessToken else {
            errorMessage = "Not signed in"
            return
        }
        errorMessage = nil
        phase = .loading

        let animal = favoriteAnimal.trimmingCharacters(in: .whitespaces).isEmpty
            ? "rabbit" : favoriteAnimal
        let place  = favoritePlace.trimmingCharacters(in: .whitespaces).isEmpty
            ? "enchanted forest" : favoritePlace
        let parentPrompt = "A gentle bedtime story about a \(animal) in a \(place)."

        let config = StoryConfig(
            childId: child.id,
            name: child.name,
            age: child.age,
            storytellingTone: "calming",
            parentPrompt: parentPrompt,
            initialState: selectedMood.rawValue,
            drawingPrompts: nil,
            characters: nil,
            minigameFrequency: "none",
            targetDuration: 15,
            cameraEnabled: eyeTracking.isCameraEnabled,
            mode: "bedtime",
            lessonName: nil,
            lessonDescription: nil,
            curriculumLessonId: nil
        )

        do {
            let story = try await APIService.shared.generateStory(config: config, token: token)
            await MainActor.run {
                generatedStory = story
                phase = .playing
            }
        } catch {
            await MainActor.run {
                errorMessage = "Could not start story: \(error.localizedDescription)"
                phase = .setup
            }
        }
    }

    // MARK: - Finalize

    private func finalize(story: Story, drift: [Double], duration: TimeInterval) async {
        let finalDrift = Int(drift.last ?? 0)
        let history   = drift.map { Int($0) }
        if let token = authManager.accessToken {
            try? await APIService.shared.updateStory(
                storyId: story.id, completed: true,
                duration: Int(duration), finalDriftScore: finalDrift,
                driftScoreHistory: history, token: token
            )
        }
        await MainActor.run {
            onComplete(drift, duration)
            dismiss()
        }
    }
}
