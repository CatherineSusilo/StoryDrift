import SwiftUI
import AVFoundation

// MARK: - API response models

struct TickResponse: Codable {
    let segment: String
    let imageUrl: String?
    let audioUrl: String?
    let strategy: String
    let score: Int
    let trajectory: String
    let lessonProgress: Int?
    let minigame: MinigameTrigger?
    let sessionComplete: Bool
}

struct SessionStartResponse: Codable {
    let sessionId: String
    let mode: String
}

// MARK: - EducationalStorySessionView

/// Runs the educational story graph loop:
/// every 45 seconds → tick → display segment + image → minigame (if any) → repeat.
struct EducationalStorySessionView: View {
    let child: ChildProfile
    let lesson: LessonDefinition
    let onComplete: (EducationalSummary) -> Void

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var vitalsManager: VitalsManager

    // Session state
    @State private var sessionId: String? = nil
    @State private var phase: SessionPhase = .loading

    // Story display
    @State private var currentSegment = ""
    @State private var currentImageUrl: String? = nil
    @State private var lessonProgress: Int = 0
    @State private var engagementScore: Int = 50
    @State private var strategy: String = ""

    // Minigame
    @State private var activeTrigger: MinigameTrigger? = nil
    @State private var showMinigame = false

    // Audio
    @State private var audioPlayer: AVAudioPlayer?

    // Tick timer
    @State private var tickTimer: Timer? = nil
    @State private var elapsedSeconds: Int = 0
    @State private var tickInterval: TimeInterval = 45

    // Score history for summary
    @State private var engagementHistory: [Int] = []

    enum SessionPhase { case loading, story, minigame, complete, error(String) }

    var body: some View {
        ZStack {
            // Background
            backgroundView

            // Content
            switch phase {
            case .loading:
                loadingOverlay
            case .story:
                storyContent
            case .minigame:
                Color.clear // minigame shown as overlay below
            case .complete:
                Color.clear
            case .error(let msg):
                errorView(msg)
            }

            // Minigame overlay (above story)
            if showMinigame, let trigger = activeTrigger {
                MinigameOverlay(trigger: trigger) { result in
                    handleMinigameComplete(result)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showMinigame)
        .onAppear { Task { await startSession() } }
        .onDisappear { tearDown() }
    }

    // MARK: - Background

    private var backgroundView: some View {
        ZStack {
            if let url = currentImageUrl.flatMap({ URL(string: $0) }) {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    learningGradient
                }
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.45).ignoresSafeArea())
            } else {
                learningGradient.ignoresSafeArea()
            }
        }
        .animation(.easeInOut(duration: 1.5), value: currentImageUrl)
    }

    private var learningGradient: some View {
        LinearGradient(
            colors: engagementColor.map { [$0.opacity(0.8), $0.opacity(0.4)] } ?? [
                Color(red: 0.05, green: 0.15, blue: 0.35),
                Color(red: 0.1, green: 0.3, blue: 0.5),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var engagementColor: Color? {
        if engagementScore <= 30 { return Color(red: 0.4, green: 0.4, blue: 0.5) }
        if engagementScore <= 60 { return Color(red: 0.2, green: 0.45, blue: 0.7) }
        if engagementScore <= 85 { return Color(red: 0.1, green: 0.6, blue: 0.5) }
        return Color(red: 0.6, green: 0.3, blue: 0.1)
    }

    // MARK: - Loading overlay

    private var loadingOverlay: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
            Text("Preparing "\(lesson.name)"…")
                .font(.custom("Georgia", size: 18))
                .foregroundColor(.white)
        }
    }

    // MARK: - Story content

    private var storyContent: some View {
        VStack(spacing: 0) {
            // Top bar
            topBar

            Spacer()

            // Segment text
            if !currentSegment.isEmpty {
                Text(currentSegment)
                    .font(.custom("Georgia", size: 21))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                    .background(Color.black.opacity(0.35))
                    .cornerRadius(18)
                    .padding(.horizontal, 16)
                    .transition(.opacity)
                    .id(currentSegment)
                    .animation(.easeInOut(duration: 0.6), value: currentSegment)
            }

            Spacer()

            // Bottom bar
            bottomBar
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            // Lesson pill
            HStack(spacing: 6) {
                Text(lesson.emoji)
                Text(lesson.name)
                    .font(Theme.bodyFont(size: 13))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.black.opacity(0.35)))

            Spacer()

            // Elapsed
            Text(formatTime(elapsedSeconds))
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.black.opacity(0.3)))
        }
        .padding(.horizontal, 16)
        .padding(.top, 52)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            // Lesson progress bar
            VStack(spacing: 6) {
                HStack {
                    Text("Lesson progress")
                        .font(Theme.bodyFont(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                    Text("\(lessonProgress)%")
                        .font(Theme.bodyFont(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.15)).frame(height: 7)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(colors: [.cyan, .green], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(lessonProgress) / 100, height: 7)
                            .animation(.spring(response: 0.8), value: lessonProgress)
                    }
                }
                .frame(height: 7)
            }

            // Engagement badge
            HStack(spacing: 8) {
                Circle()
                    .fill(engagementDotColor)
                    .frame(width: 9, height: 9)
                Text(engagementLabel)
                    .font(Theme.bodyFont(size: 13))
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Text(strategy.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(Theme.bodyFont(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
    }

    private var engagementDotColor: Color {
        if engagementScore <= 30 { return .red }
        if engagementScore <= 60 { return .orange }
        if engagementScore <= 85 { return .green }
        return .yellow
    }

    private var engagementLabel: String {
        if engagementScore <= 30 { return "Needs attention" }
        if engagementScore <= 60 { return "Following along" }
        if engagementScore <= 85 { return "Actively learning ★" }
        return "Very stimulated"
    }

    // MARK: - Error view

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text(msg)
                .font(.custom("Georgia", size: 17))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Session lifecycle

    private func startSession() async {
        guard let token = authManager.accessToken else {
            phase = .error("Not authenticated")
            return
        }

        do {
            let body: [String: Any] = [
                "mode": "educational",
                "childProfile": [
                    "childId": child.id,
                    "name": child.name,
                    "age": child.age,
                    "favoriteCharacter": (child as? ChildProfile)?.name ?? "a curious animal",
                ],
                "lessonName": lesson.name,
                "lessonDescription": lesson.description,
            ]

            let data = try await APIService.shared.post(
                path: "/api/story-session/start",
                body: body,
                token: token
            )
            let resp = try JSONDecoder().decode(SessionStartResponse.self, from: data)
            sessionId = resp.sessionId
            vitalsManager.startMonitoring(childId: child.id)
            phase = .story
            startTickTimer()
        } catch {
            phase = .error("Could not start lesson: \(error.localizedDescription)")
        }
    }

    private func startTickTimer() {
        // Immediate first tick
        Task { await runTick() }

        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedSeconds += 1
            if elapsedSeconds % Int(tickInterval) == 0 && !showMinigame {
                Task { await runTick() }
            }
        }
    }

    private func runTick() async {
        guard let sid = sessionId, let token = authManager.accessToken else { return }

        let cameraEnabled = vitalsManager.isCameraEnabled && vitalsManager.signalQuality > 0.2
        let biometrics: [String: Any] = cameraEnabled ? [
            "pulse_rate":     vitalsManager.heartRate > 0 ? vitalsManager.heartRate : NSNull(),
            "breathing_rate": vitalsManager.breathingRate > 0 ? vitalsManager.breathingRate : NSNull(),
            "movement_level": 0.3,
            "signal_quality": vitalsManager.signalQuality,
        ] : [:]

        do {
            let data = try await APIService.shared.post(
                path: "/api/story-session/\(sid)/tick?includeAudio=1",
                body: ["biometrics": biometrics, "cameraEnabled": cameraEnabled],
                token: token
            )
            let resp = try JSONDecoder().decode(TickResponse.self, from: data)
            await MainActor.run { applyTickResponse(resp) }
        } catch {
            print("⚠️ Tick error: \(error)")
        }
    }

    @MainActor
    private func applyTickResponse(_ resp: TickResponse) {
        withAnimation {
            currentSegment   = resp.segment
            currentImageUrl  = resp.imageUrl
            lessonProgress   = resp.lessonProgress ?? lessonProgress
            engagementScore  = resp.score
            strategy         = resp.strategy
        }
        engagementHistory.append(resp.score)

        // Play audio if present
        if let audioUrl = resp.audioUrl, let audioData = Data(base64Encoded: audioUrl.components(separatedBy: ",").last ?? "") {
            playAudio(data: audioData)
        }

        // Session complete
        if resp.sessionComplete {
            tickTimer?.invalidate()
            vitalsManager.stopMonitoring()
            phase = .complete
            onComplete(EducationalSummary(
                lessonName: lesson.name,
                lessonEmoji: lesson.emoji,
                lessonProgress: lessonProgress,
                engagementHistory: engagementHistory,
                sessionDurationSeconds: elapsedSeconds
            ))
            return
        }

        // Minigame
        if let trigger = resp.minigame {
            activeTrigger = trigger
            showMinigame = true
            // Pause tick timer while minigame is active
            tickTimer?.invalidate()
        }
    }

    private func handleMinigameComplete(_ result: MinigameResult) {
        showMinigame = false
        activeTrigger = nil

        // Send result to backend
        if let sid = sessionId, let token = authManager.accessToken {
            Task {
                let body: [String: Any] = [
                    "type": result.type.rawValue,
                    "completed": result.completed,
                    "correct": result.correct as Any,
                    "skipped": result.skipped,
                    "responseData": result.responseData as Any,
                ]
                _ = try? await APIService.shared.post(
                    path: "/api/story-session/\(sid)/minigame-result",
                    body: body, token: token
                )
            }
        }

        // Resume tick timer
        startTickTimer()
    }

    private func tearDown() {
        tickTimer?.invalidate()
        audioPlayer?.stop()
        vitalsManager.stopMonitoring()

        if let sid = sessionId, let token = authManager.accessToken {
            Task {
                _ = try? await APIService.shared.post(
                    path: "/api/story-session/\(sid)/end",
                    body: [:], token: token
                )
            }
        }
    }

    // MARK: - Audio

    private func playAudio(data: Data) {
        DispatchQueue.main.async {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                audioPlayer = try AVAudioPlayer(data: data)
                audioPlayer?.play()
            } catch {
                print("Audio error: \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Summary model

struct EducationalSummary {
    let lessonName: String
    let lessonEmoji: String
    let lessonProgress: Int
    let engagementHistory: [Int]
    let sessionDurationSeconds: Int
}
