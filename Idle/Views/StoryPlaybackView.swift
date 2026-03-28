import SwiftUI
import AVFoundation

struct StoryPlaybackView: View {
    @EnvironmentObject var vitalsManager: VitalsManager
    @EnvironmentObject var authManager: AuthManager
    let story: Story
    let onComplete: ([Double], TimeInterval) -> Void

    @State private var currentParagraphIndex = 0
    @State private var isPlaying = true
    @State private var elapsedTime: TimeInterval = 0
    @State private var showMenu = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var timer: Timer?
    @State private var driftHistory: [Double] = []
    @State private var paragraphElapsed: TimeInterval = 0

    // Live per-paragraph image URLs — starts from story.images, filled by polling
    @State private var paragraphImages: [String] = []
    @State private var imagePollingTimer: Timer? = nil

    // Minigame
    @State private var activeTrigger: MinigameTrigger? = nil
    @State private var showMinigame = false
    @State private var paragraphsSinceLastMinigame = 0
    @State private var isGeneratingMinigame = false

    @StateObject private var vitalsTracker = StoryVitalsTracker()

    // How many paragraphs between minigames based on story.minigameFrequency
    private var minigameGap: Int {
        switch story.minigameFrequency {
        case "every_paragraph": return 1
        case "every_3rd":       return 3
        case "every_5th":       return 5
        default:                return Int.max  // none
        }
    }

    private var minSecondsPerParagraph: TimeInterval {
        let targetSeconds = TimeInterval((story.targetDuration ?? 15) * 60)
        let count = max(1, story.paragraphs.count)
        return targetSeconds / TimeInterval(count)
    }

    private var currentParagraph: StoryParagraph? {
        guard currentParagraphIndex < story.paragraphs.count else { return nil }
        return story.paragraphs[currentParagraphIndex]
    }

    /// Live image for the current paragraph — from polled results or story.images fallback.
    private var currentImage: String? {
        let idx = currentParagraphIndex
        // Use live polled image if available
        if paragraphImages.indices.contains(idx), !paragraphImages[idx].isEmpty {
            return paragraphImages[idx]
        }
        // Fall back to pre-baked story images
        guard !story.images.isEmpty else { return nil }
        let clamped = min(idx, story.images.count - 1)
        let raw = story.images[clamped]
        return raw.isEmpty ? nil : raw
    }

    private var progress: Double {
        guard !story.paragraphs.isEmpty else { return 0 }
        return Double(currentParagraphIndex) / Double(story.paragraphs.count)
    }

    var body: some View {
        ZStack {
            // Per-paragraph background with smooth 1.5s crossfade
            StoryImageView.bedtime(imageUrl: currentImage, driftScore: Int(progress * 100))

            VStack(spacing: 0) {

            VStack(spacing: 0) {
                // Top Bar
                HStack {
                    Button(action: { withAnimation(.spring(response: 0.3)) { showMenu = true } }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .padding()
                            .background(Circle().fill(Color.black.opacity(0.3)))
                    }

                    Spacer()

                    // Time elapsed
                    Text(formatTime(elapsedTime))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.3)))
                }
                .padding()

                Spacer()

                // Story Text
                VStack(spacing: 24) {
                    if let paragraph = currentParagraph {
                        Text(paragraph.text)
                            .font(.custom("Georgia", size: 22))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                            .transition(.opacity)
                            .id(currentParagraphIndex)
                    }
                }
                .frame(maxHeight: 300)

                Spacer()

                // Drift Meter
                DriftMeterView(driftScore: vitalsManager.driftScore, isCompact: true)
                    .padding(.horizontal)

                // Progress Bar
                VStack(spacing: 12) {
                    ProgressView(value: progress)
                        .tint(.cyan)
                        .scaleEffect(y: 2)

                    HStack {
                        Text("Paragraph \(currentParagraphIndex + 1) of \(story.paragraphs.count)")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text(vitalsManager.getDriftStatus())
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.cyan)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }

            // ── Minigame overlay ─────────────────────────────────────────────
            if showMinigame, let trigger = activeTrigger {
                MinigameOverlay(trigger: trigger) { result in
                    handleMinigameComplete(result)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .zIndex(50)
            }

            // ── Custom menu overlay ──────────────────────────────────────────
            if showMenu {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.spring(response: 0.3)) { showMenu = false } }
                    .transition(.opacity)

                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: 0) {
                        // Handle
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 40, height: 4)
                            .padding(.top, 14)
                            .padding(.bottom, 20)

                        menuButton(
                            icon: isPlaying ? "pause.fill" : "play.fill",
                            label: isPlaying ? "Pause" : "Resume",
                            color: .white
                        ) {
                            togglePlayback()
                            withAnimation { showMenu = false }
                        }

                        Divider().background(Color.white.opacity(0.15))

                        menuButton(
                            icon: "forward.fill",
                            label: "Next Paragraph",
                            color: .white
                        ) {
                            paragraphElapsed = 0
                            nextParagraph()
                            withAnimation { showMenu = false }
                        }

                        Divider().background(Color.white.opacity(0.15))

                        menuButton(
                            icon: "xmark.circle.fill",
                            label: "End Story",
                            color: Color(red: 1, green: 0.35, blue: 0.35)
                        ) {
                            showMenu = false
                            completeStory()
                        }

                        // Safe-area spacer
                        Color.clear.frame(height: 34)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color(red: 0.1, green: 0.1, blue: 0.18).opacity(0.97))
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showMenu)
        .animation(.easeInOut(duration: 0.35), value: showMinigame)
        .onAppear { startStory() }
        .onDisappear { stopStory() }
    }

    // MARK: - Menu button helper

    private func menuButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 28)
                Text(label)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(color)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
    }

    private func startStory() {
        // Pre-fill paragraphImages from any already-available story images
        paragraphImages = Array(repeating: "", count: story.paragraphs.count)
        for (i, url) in story.images.enumerated() where i < paragraphImages.count {
            paragraphImages[i] = url
        }

        vitalsManager.startMonitoring(childId: story.childId)
        vitalsTracker.startTracking(storyId: story.id, childId: story.childId, vitalsManager: vitalsManager)

        // Poll for background Gemini images if the story has a pending imageJobId
        if let jobId = story.imageJobId, !jobId.isEmpty {
            startImagePolling(jobId: jobId)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if isPlaying && !showMinigame {
                elapsedTime += 1
                paragraphElapsed += 1
                driftHistory.append(vitalsManager.driftScore)

                if vitalsManager.driftScore >= 90 { completeStory(); return }

                if paragraphElapsed >= minSecondsPerParagraph {
                    paragraphElapsed = 0
                    nextParagraph()
                }

                #if DEBUG
                if story.parentPrompt.hasPrefix("DEBUG_2MIN:") && elapsedTime >= 120 { completeStory() }
                #endif
            }
        }

        playCurrentParagraph()
    }

    private func startImagePolling(jobId: String) {
        guard let token = authManager.accessToken else { return }
        imagePollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task {
                guard let url = URL(string: "\(APIService.baseURL)/api/generate/story-images/\(jobId)") else { return }
                var req = URLRequest(url: url)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                guard let (data, _) = try? await URLSession.shared.data(for: req),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let images = json["images"] as? [String] else { return }
                await MainActor.run {
                    for (i, imgUrl) in images.enumerated() where i < paragraphImages.count && !imgUrl.isEmpty {
                        if paragraphImages[i].isEmpty { paragraphImages[i] = imgUrl }
                    }
                    if json["complete"] as? Bool == true { stopImagePolling() }
                }
            }
        }
    }

    private func stopImagePolling() {
        imagePollingTimer?.invalidate()
        imagePollingTimer = nil
    }

    private func stopStory() {
        timer?.invalidate(); timer = nil
        stopImagePolling()
        audioPlayer?.stop()
        vitalsManager.stopMonitoring()
        vitalsTracker.stopTracking()
    }
    
    private func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            audioPlayer?.play()
        } else {
            audioPlayer?.pause()
        }
    }
    
    private func nextParagraph() {
        guard currentParagraphIndex < story.paragraphs.count - 1 else {
            completeStory()
            return
        }

        paragraphElapsed = 0
        paragraphsSinceLastMinigame += 1

        withAnimation {
            currentParagraphIndex += 1
        }

        playCurrentParagraph()

        // Check if a minigame should fire after this paragraph
        checkAndTriggerMinigame()
    }

    private func checkAndTriggerMinigame() {
        guard !showMinigame,
              !isGeneratingMinigame,
              minigameGap < Int.max,
              paragraphsSinceLastMinigame >= minigameGap,
              let paragraph = currentParagraph,
              let token = authManager.accessToken else { return }

        isGeneratingMinigame = true

        Task {
            do {
                let body: [String: Any] = [
                    "paragraphText":  paragraph.text,
                    "storyContext":   story.parentPrompt,
                    "childAge":       6,
                    "paragraphIndex": currentParagraphIndex,
                ]
                let data = try await APIService.shared.post(
                    path: "/api/generate/minigame",
                    body: body,
                    token: token
                )
                let trigger = try JSONDecoder().decode(MinigameTrigger.self, from: data)
                await MainActor.run {
                    activeTrigger  = trigger
                    showMinigame   = true
                    paragraphsSinceLastMinigame = 0
                    isGeneratingMinigame = false
                    audioPlayer?.pause()
                }
            } catch {
                print("⚠️ Minigame generation failed: \(error)")
                await MainActor.run { isGeneratingMinigame = false }
            }
        }
    }

    private func handleMinigameComplete(_ result: MinigameResult) {
        showMinigame   = false
        activeTrigger  = nil
        audioPlayer?.play()
    }
    
    private func playCurrentParagraph() {
        audioPlayer?.stop()
        guard let paragraph = currentParagraph else { return }

        if let rawUrl = paragraph.audioUrl, !rawUrl.isEmpty {
            // Resolve relative /images/... paths to full server URL
            let fullUrl: URL?
            if rawUrl.hasPrefix("http") {
                fullUrl = URL(string: rawUrl)
            } else {
                fullUrl = URL(string: "\(APIService.baseURL)\(rawUrl)")
            }
            if let url = fullUrl {
                playAudio(url: url)
                return
            }
        }
        // No audio URL — fall back to slow AVSpeechSynthesizer
        speakText(paragraph.text)
    }

    private func playAudio(url: URL) {
        // Activate audio session before fetching/playing
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("⚠️ AVAudioSession setup failed: \(error)")
        }

        // Use URLCache so repeated plays don't re-download
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data, error == nil else {
                print("⚠️ Audio download failed: \(error?.localizedDescription ?? "unknown")")
                DispatchQueue.main.async { self.speakText(self.currentParagraph?.text ?? "") }
                return
            }
            DispatchQueue.main.async {
                do {
                    self.audioPlayer = try AVAudioPlayer(data: data)
                    self.audioPlayer?.enableRate = true
                    self.audioPlayer?.rate = 1.0  // ElevenLabs already slowed at generation time
                    self.audioPlayer?.prepareToPlay()
                    self.audioPlayer?.play()
                } catch {
                    print("⚠️ AVAudioPlayer error: \(error)")
                    self.speakText(self.currentParagraph?.text ?? "")
                }
            }
        }.resume()
    }

    private func speakText(_ text: String) {
        // Slow, gentle TTS fallback (used when no ElevenLabs audio available)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.35        // slower than default 0.5
        utterance.pitchMultiplier = 0.85
        utterance.volume = 0.9
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.speak(utterance)
    }
    
    private func completeStory() {
        stopStory()
        onComplete(driftHistory, elapsedTime)
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    
    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

#Preview {
    StoryPlaybackView(
        story: Story(
            id: "1", childId: "child1",
            storyTitle: "The Magical Forest",
            storyContent: "Once upon a time, in a magical forest...",
            parentPrompt: "Loves unicorns",
            storytellingTone: "calming",
            initialState: "normal",
            startTime: Date(),
            endTime: nil, duration: nil, sleepOnsetTime: nil,
            completed: false,
            initialDriftScore: 0, finalDriftScore: 0,
            driftScoreHistory: [], generatedImages: [],
            modelUsed: nil,
            createdAt: Date(), updatedAt: Date()
        ),
        onComplete: { _, _ in }
    )
    .environmentObject(VitalsManager())
    .environmentObject(AuthManager())
}
