import SwiftUI
import AVFoundation

// MARK: - BedtimeStorySessionView
//
// Clean, distraction-free bedtime story experience.
// No interactive elements, no minigames, no choices.
// Just story text, a fading scene image, ambient audio,
// and the drift meter — all gently guiding toward sleep.

struct BedtimeStorySessionView: View {
    let child: ChildProfile
    let onComplete: ([Double], TimeInterval) -> Void

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var vitalsManager: VitalsManager

    // Session
    @State private var sessionId: String? = nil
    @State private var phase: BedtimePhase = .setup

    // Story display
    @State private var currentSegment = ""
    @State private var currentImageUrl: String? = nil
    @State private var driftScore: Int = 0
    @State private var driftTrajectory = "flat"
    @State private var arcPosition = "opening"

    // Setup form
    @State private var favoriteAnimal = ""
    @State private var favoritePlace  = ""
    @State private var selectedMood: TonightsMood = .normal

    // Playback
    @State private var audioPlayer: AVAudioPlayer?
    @State private var tickTimer: Timer?
    @State private var elapsedSeconds: Int = 0
    @State private var driftHistory: [Double] = []
    @State private var isFadingToBlack = false

    enum BedtimePhase { case setup, loading, playing, complete }
    enum TonightsMood: String, CaseIterable {
        case wound_up = "wound_up"
        case normal   = "normal"
        case almost_there = "almost_there"

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
            case .setup:    setupView
            case .loading:  loadingView
            case .playing:  storyView
            case .complete: Color.black.ignoresSafeArea()
            }

            // Fade-to-black overlay when sleep is detected
            if isFadingToBlack {
                Color.black
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 1.5), value: isFadingToBlack)
        .animation(.easeInOut(duration: 0.5), value: phase)
        .onDisappear { tearDown() }
    }

    // MARK: - Setup view

    private var setupView: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("🌙 Bedtime Story")
                            .font(Theme.titleFont(size: 28))
                            .foregroundColor(Theme.ink)
                        Text("for \(child.name)")
                            .font(Theme.bodyFont(size: 17))
                            .foregroundColor(Theme.inkMuted)
                    }
                    .padding(.top, 20)

                    // Favourite animal
                    formField(
                        icon: "pawprint.fill",
                        label: "Favourite animal",
                        placeholder: "e.g. fox, rabbit, elephant",
                        text: $favoriteAnimal
                    )

                    // Favourite place
                    formField(
                        icon: "map.fill",
                        label: "Favourite place",
                        placeholder: "e.g. enchanted forest, moon, cosy cottage",
                        text: $favoritePlace
                    )

                    // Tonight's mood
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

                    Spacer(minLength: 16)

                    // Begin button
                    Button {
                        Task { await startSession() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "moon.zzz.fill")
                            Text("Begin Story")
                                .fontWeight(.semibold)
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
                Text("🌙")
                    .font(.system(size: 60))
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.4)
                Text("Setting the scene…")
                    .font(.custom("Georgia", size: 18))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }

    // MARK: - Story view (clean, no interactive elements)

    private var storyView: some View {
        ZStack {
            // Scene background
            sceneBackground

            VStack(spacing: 0) {
                Spacer()

                // Story text — centred, soft, cinematic
                if !currentSegment.isEmpty {
                    Text(currentSegment)
                        .font(.custom("Georgia", size: 22))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(8)
                        .padding(.horizontal, 32)
                        .shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 3)
                        .transition(.opacity)
                        .id(currentSegment)
                        .animation(.easeInOut(duration: 1.2), value: currentSegment)
                }

                Spacer()

                // Bottom: drift meter only — no controls, no buttons
                driftBar
            }
        }
    }

    private var sceneBackground: some View {
        ZStack {
            if let url = currentImageUrl.flatMap({ URL(string: $0) }) {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { nightGradient }
                .ignoresSafeArea()
            } else {
                nightGradient.ignoresSafeArea()
            }

            // Dark overlay intensifies as drift score rises
            let overlayOpacity = 0.4 + Double(driftScore) / 100 * 0.45
            Color.black.opacity(overlayOpacity).ignoresSafeArea()
                .animation(.easeInOut(duration: 4), value: driftScore)
        }
    }

    private var nightGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.03, blue: 0.12),
                Color(red: 0.06, green: 0.02, blue: 0.18),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var driftBar: some View {
        VStack(spacing: 8) {
            // Drift score label fades at high score
            HStack {
                Text("Drifting…")
                    .font(Theme.bodyFont(size: 13))
                    .foregroundColor(.white.opacity(max(0.1, 0.6 - Double(driftScore) / 100 * 0.5)))
                Spacer()
                Text("\(driftScore)%")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(max(0.1, 0.5 - Double(driftScore) / 100 * 0.4)))
            }
            .padding(.horizontal, 28)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 4)
                    Capsule()
                        .fill(LinearGradient(colors: [Color.indigo.opacity(0.8), Color.purple.opacity(0.5)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(driftScore) / 100, height: 4)
                        .animation(.easeInOut(duration: 3), value: driftScore)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 28)
        }
        .padding(.bottom, 44)
        .opacity(driftScore > 90 ? 0 : 1)
        .animation(.easeInOut(duration: 4), value: driftScore)
    }

    // MARK: - Session logic

    private func startSession() async {
        guard let token = authManager.accessToken else { return }
        phase = .loading

        let body: [String: Any] = [
            "mode": "bedtime",
            "childProfile": [
                "childId": child.id,
                "name": child.name,
                "age": child.age,
                "favoriteAnimal": favoriteAnimal.isEmpty ? "rabbit" : favoriteAnimal,
                "favoritePlace":  favoritePlace.isEmpty  ? "enchanted forest" : favoritePlace,
                "tonightsMood":   selectedMood.rawValue,
            ],
        ]

        do {
            let data = try await APIService.shared.post(
                path: "/api/story-session/start", body: body, token: token)
            let resp = try JSONDecoder().decode(SessionStartResponse.self, from: data)
            sessionId = resp.sessionId
            vitalsManager.startMonitoring(childId: child.id)
            phase = .playing
            startTickTimer()
        } catch {
            phase = .setup
        }
    }

    private func startTickTimer() {
        Task { await runTick() }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedSeconds += 1
            driftHistory.append(vitalsManager.driftScore)

            // Tick every 60 seconds
            if elapsedSeconds % 60 == 0 {
                Task { await runTick() }
            }
        }
    }

    private func runTick() async {
        guard let sid = sessionId, let token = authManager.accessToken else { return }

        let cameraEnabled = vitalsManager.isCameraEnabled && vitalsManager.signalQuality > 20
        let biometrics: [String: Any] = cameraEnabled ? [
            "pulse_rate":     vitalsManager.heartRate > 0 ? vitalsManager.heartRate : NSNull(),
            "breathing_rate": vitalsManager.breathingRate > 0 ? vitalsManager.breathingRate : NSNull(),
            "movement_level": 0.2,
            "signal_quality": vitalsManager.signalQuality,
        ] : [:]

        do {
            let data = try await APIService.shared.post(
                path: "/api/story-session/\(sid)/tick?includeAudio=1",
                body: ["biometrics": biometrics, "cameraEnabled": cameraEnabled], token: token)
            let resp = try JSONDecoder().decode(TickResponse.self, from: data)
            await MainActor.run { applyTick(resp) }
        } catch {
            print("Bedtime tick error: \(error)")
        }
    }

    @MainActor
    private func applyTick(_ resp: TickResponse) {
        withAnimation {
            currentSegment  = resp.segment
            currentImageUrl = resp.imageUrl
            driftScore      = resp.score
            driftTrajectory = resp.trajectory
        }

        if let audioUrl = resp.audioUrl,
           let base64   = audioUrl.components(separatedBy: ",").last,
           let audioData = Data(base64Encoded: base64) {
            playAudio(data: audioData)
        }

        if resp.sessionComplete {
            endSession()
        }
    }

    private func endSession() {
        // Fade to black silently
        withAnimation(.easeIn(duration: 3.0)) {
            isFadingToBlack = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            tearDown()
            onComplete(driftHistory.map { $0 }, TimeInterval(elapsedSeconds))
        }
    }

    private func tearDown() {
        tickTimer?.invalidate()
        audioPlayer?.stop()
        vitalsManager.stopMonitoring()
        if let sid = sessionId, let token = authManager.accessToken {
            Task { _ = try? await APIService.shared.post(
                path: "/api/story-session/\(sid)/end", body: [:], token: token) }
        }
    }

    private func playAudio(data: Data) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.play()
        } catch {
            print("Audio error: \(error)")
        }
    }
}
