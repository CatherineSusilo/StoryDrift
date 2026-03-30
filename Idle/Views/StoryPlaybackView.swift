import SwiftUI
import AVFoundation

// MARK: - Audio delegate coordinator (must be a class — AVAudioPlayerDelegate : NSObjectProtocol)

final class AudioFinishDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard flag else { return }
        DispatchQueue.main.async { self.onFinish?() }
    }
}

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

    // Live per-paragraph image URLs — filled by polling
    @State private var paragraphImages: [String] = []
    @State private var imagePollingTimer: Timer? = nil

    // Minigame
    @State private var activeTrigger: MinigameTrigger? = nil
    @State private var showMinigame = false
    @State private var paragraphsSinceLastMinigame = 0
    @State private var isGeneratingMinigame = false
    /// When true, advance to the next paragraph as soon as any shown minigame is dismissed
    @State private var pendingAdvanceAfterMinigame = false

    @StateObject private var vitalsTracker = StoryVitalsTracker()
    @State private var audioDelegate = AudioFinishDelegate()

    // MARK: - Computed

    private var minigameGap: Int {
        switch story.minigameFrequency {
        case "every_paragraph": return 1
        case "every_3rd":       return 3
        case "every_5th":       return 5
        default:                return Int.max
        }
    }

    private var minSecondsPerParagraph: TimeInterval {
        let targetSeconds = TimeInterval((story.targetDuration ?? 15) * 60)
        return targetSeconds / TimeInterval(max(1, story.paragraphs.count))
    }

    private var currentParagraph: StoryParagraph? {
        guard currentParagraphIndex < story.paragraphs.count else { return nil }
        return story.paragraphs[currentParagraphIndex]
    }

    private var currentImage: String? {
        let idx = currentParagraphIndex
        if paragraphImages.indices.contains(idx), !paragraphImages[idx].isEmpty {
            return paragraphImages[idx]
        }
        guard !story.images.isEmpty else { return nil }
        let raw = story.images[min(idx, story.images.count - 1)]
        return raw.isEmpty ? nil : raw
    }

    private var progress: Double {
        guard !story.paragraphs.isEmpty else { return 0 }
        return Double(currentParagraphIndex) / Double(story.paragraphs.count)
    }

    // MARK: - State for stats panel
    @State private var showStats = false

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let safeBottom = geo.safeAreaInsets.bottom
            let safeTop    = geo.safeAreaInsets.top
            let safeLeft   = geo.safeAreaInsets.leading
            let safeRight  = geo.safeAreaInsets.trailing
            let btnPad: CGFloat = 16   // padding from safe-area edge to button centre

            ZStack {
                // ── Full-screen background ───────────────────────────────────
                StoryImageView.bedtime(imageUrl: currentImage, driftScore: Int(progress * 100))
                    .frame(width: geo.size.width + safeLeft + safeRight,
                           height: geo.size.height + safeTop + safeBottom)
                    .offset(x: -safeLeft, y: -safeTop)
                    .zIndex(0)

                // ── Timer — top right, inside safe area ─────────────────────
                VStack {
                    HStack {
                        Spacer()
                        Text(formatTime(elapsedTime))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                            .padding(.top, max(safeTop, 12))
                            .padding(.trailing, max(safeRight, 12) + btnPad)
                    }
                    Spacer()
                }
                .zIndex(1)

                // ── Caption — bottom centre, movie-subtitle style ────────────
                VStack {
                    Spacer()
                    if let paragraph = currentParagraph {
                        Text(paragraph.text)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, max(safeLeft, safeRight) + 70)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(
                                    colors: [.clear, Color.black.opacity(0.65)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .transition(.opacity)
                            .id(currentParagraphIndex)
                    }
                    // Bottom spacer = safe area + button height so text sits above buttons
                    Color.clear.frame(height: safeBottom + 52)
                }
                .zIndex(1)

                // ── Bottom-left: menu button ─────────────────────────────────
                VStack {
                    Spacer()
                    HStack {
                        Button(action: { withAnimation(.spring(response: 0.3)) { showMenu.toggle() } }) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.black.opacity(0.55)))
                                .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 3)
                        }
                        .padding(.leading, max(safeLeft, 8) + btnPad)
                        .padding(.bottom, max(safeBottom, 8) + btnPad)
                        Spacer()
                    }
                }
                .zIndex(2)

                // ── Bottom-right: stats button ───────────────────────────────
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { withAnimation(.spring(response: 0.3)) { showStats.toggle() } }) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.black.opacity(0.55)))
                                .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 3)
                        }
                        .padding(.trailing, max(safeRight, 8) + btnPad)
                        .padding(.bottom, max(safeBottom, 8) + btnPad)
                    }
                }
                .zIndex(2)

                // ── Minigame overlay ─────────────────────────────────────────
                if showMinigame, let trigger = activeTrigger {
                    MinigameOverlay(trigger: trigger) { result in
                        handleMinigameComplete(result)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(50)
                }

                // ── Menu sheet (bottom-up) ───────────────────────────────────
                if showMenu {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(.spring(response: 0.3)) { showMenu = false } }
                        .transition(.opacity)
                        .zIndex(90)

                    VStack(spacing: 0) {
                        Spacer()
                        VStack(spacing: 0) {
                            Capsule()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 36, height: 4)
                                .padding(.top, 12)
                                .padding(.bottom, 16)

                            menuButton(icon: isPlaying ? "pause.fill" : "play.fill",
                                       label: isPlaying ? "Pause" : "Resume",
                                       color: .white) {
                                togglePlayback()
                                withAnimation { showMenu = false }
                            }
                            Divider().background(Color.white.opacity(0.15))

                            menuButton(icon: "forward.fill", label: "Next Paragraph", color: .white) {
                                paragraphElapsed = 0
                                nextParagraph()
                                withAnimation { showMenu = false }
                            }
                            Divider().background(Color.white.opacity(0.15))

                            menuButton(icon: "xmark.circle.fill", label: "End Story",
                                       color: Color(red: 1, green: 0.35, blue: 0.35)) {
                                showMenu = false
                                completeStory()
                            }
                            Color.clear.frame(height: max(safeBottom, 16))
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color(red: 0.08, green: 0.08, blue: 0.16).opacity(0.97))
                        )
                        .padding(.horizontal, max(safeLeft, safeRight) + 8)
                        .padding(.bottom, 8)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
                }

                // ── Stats panel (bottom-up) ──────────────────────────────────
                if showStats {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(.spring(response: 0.3)) { showStats = false } }
                        .transition(.opacity)
                        .zIndex(90)

                    VStack(spacing: 0) {
                        Spacer()
                        VStack(spacing: 16) {
                            Capsule()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 36, height: 4)
                                .padding(.top, 12)

                            DriftMeterView(driftScore: vitalsManager.driftScore, isCompact: true)
                                .padding(.horizontal, 20)

                            VStack(spacing: 8) {
                                ProgressView(value: progress)
                                    .tint(.cyan)
                                    .scaleEffect(y: 2)
                                HStack {
                                    Text("Paragraph \(currentParagraphIndex + 1) of \(story.paragraphs.count)")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.7))
                                    Spacer()
                                    Text(vitalsManager.getDriftStatus())
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.cyan)
                                }
                            }
                            .padding(.horizontal, 20)

                            Color.clear.frame(height: max(safeBottom, 16))
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color(red: 0.08, green: 0.08, blue: 0.16).opacity(0.97))
                        )
                        .padding(.horizontal, max(safeLeft, safeRight) + 8)
                        .padding(.bottom, 8)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showMenu)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showStats)
            .animation(.easeInOut(duration: 0.35), value: showMinigame)
        }
        .ignoresSafeArea()
        .onAppear { startStory() }
        .onDisappear { stopStory() }
    }

    // MARK: - Menu button

    private func menuButton(icon: String, label: String, color: Color,
                             action: @escaping () -> Void) -> some View {
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

    // MARK: - Story lifecycle

    private func startStory() {
        paragraphImages = Array(repeating: "", count: story.paragraphs.count)
        for (i, url) in story.images.enumerated() where i < paragraphImages.count {
            paragraphImages[i] = url
        }

        // Initialize minigame counter so first minigame can fire on first eligible paragraph
        paragraphsSinceLastMinigame = minigameGap

        // Start vitals monitoring — use isCameraEnabled from VitalsManager (user's current setting)
        // story.cameraEnabled is the value at story creation time; isCameraEnabled is live setting
        let useSynthetic = !vitalsManager.isCameraEnabled
        let targetDuration = TimeInterval((story.targetDuration ?? 15) * 60)
        vitalsManager.startMonitoring(childId: story.childId, useSynthetic: useSynthetic, targetDuration: targetDuration)
        vitalsTracker.startTracking(storyId: story.id, childId: story.childId,
                                    vitalsManager: vitalsManager,
                                    cameraEnabled: vitalsManager.isCameraEnabled)

        if let jobId = story.imageJobId, !jobId.isEmpty {
            startImagePolling(jobId: jobId)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard self.isPlaying && !self.showMinigame else { return }
            self.elapsedTime += 1
            self.paragraphElapsed += 1
            self.driftHistory.append(self.vitalsManager.driftScore)

            if self.vitalsManager.driftScore >= 90 { self.completeStory(); return }
        }

        playCurrentParagraph()
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
        if isPlaying { audioPlayer?.play() } else { audioPlayer?.pause() }
    }

    private func nextParagraph() {
        guard currentParagraphIndex < story.paragraphs.count - 1 else {
            completeStory(); return
        }
        paragraphElapsed = 0

        // Only increment if minigames are enabled (avoid Int.max overflow)
        if minigameGap < Int.max {
            paragraphsSinceLastMinigame += 1
        }

        withAnimation { currentParagraphIndex += 1 }
        playCurrentParagraph()
    }

    /// Hooked up in playAudio() — called by AudioFinishDelegate when audio ends.
    private func audioDidFinish() {
        guard isPlaying else { return }
        if shouldTriggerMinigame() {
            pendingAdvanceAfterMinigame = true
            triggerMinigame()
        } else {
            nextParagraph()
        }
    }

    private func completeStory() {
        stopStory()
        onComplete(driftHistory, elapsedTime)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    // MARK: - Image polling

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
                    for (i, imgUrl) in images.enumerated() where i < self.paragraphImages.count && !imgUrl.isEmpty {
                        if self.paragraphImages[i].isEmpty { self.paragraphImages[i] = imgUrl }
                    }
                    if json["complete"] as? Bool == true { self.stopImagePolling() }
                }
            }
        }
    }

    private func stopImagePolling() {
        imagePollingTimer?.invalidate()
        imagePollingTimer = nil
    }

    // MARK: - Minigame

    private func shouldTriggerMinigame() -> Bool {
        return !showMinigame
            && !isGeneratingMinigame
            && minigameGap < Int.max
            && paragraphsSinceLastMinigame >= minigameGap
    }

    private func triggerMinigame() {
        guard let paragraph = currentParagraph,
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
                    path: "/api/generate/minigame", body: body, token: token)
                var trigger = try JSONDecoder().decode(MinigameTrigger.self, from: data)
                // Ensure shape_sorting always has shapes
                trigger = trigger.withFallbackShapes()
                await MainActor.run {
                    self.activeTrigger = trigger
                    self.showMinigame  = true
                    self.paragraphsSinceLastMinigame = 0
                    self.isGeneratingMinigame = false
                    self.audioPlayer?.pause()
                }
            } catch {
                print("⚠️ Minigame generation failed: \(error)")
                await MainActor.run {
                    self.isGeneratingMinigame = false
                    // If we were pending advance, still advance
                    if self.pendingAdvanceAfterMinigame {
                        self.pendingAdvanceAfterMinigame = false
                        self.nextParagraph()
                    }
                }
            }
        }
    }

    private func checkAndTriggerMinigame() {
        if shouldTriggerMinigame() {
            pendingAdvanceAfterMinigame = false
            triggerMinigame()
        }
    }

    private func handleMinigameComplete(_ result: MinigameResult) {
        showMinigame  = false
        activeTrigger = nil
        if pendingAdvanceAfterMinigame {
            pendingAdvanceAfterMinigame = false
            nextParagraph()
        } else {
            // Minigame was triggered by menu "next paragraph" — just resume audio
            audioPlayer?.play()
        }
    }

    // MARK: - Audio

    private func playCurrentParagraph() {
        audioPlayer?.stop()
        guard let paragraph = currentParagraph else { return }

        if let rawUrl = paragraph.audioUrl, !rawUrl.isEmpty {
            let fullUrl = rawUrl.hasPrefix("http")
                ? URL(string: rawUrl)
                : URL(string: "\(APIService.baseURL)\(rawUrl)")
            if let url = fullUrl { playAudio(url: url); return }
        }
        speakText(paragraph.text)
    }

    private func playAudio(url: URL) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch { print("⚠️ AVAudioSession: \(error)") }

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data, error == nil else {
                DispatchQueue.main.async { self.speakText(self.currentParagraph?.text ?? "") }
                return
            }
            DispatchQueue.main.async {
                do {
                    self.audioPlayer = try AVAudioPlayer(data: data)
                    self.audioDelegate.onFinish = { self.audioDidFinish() }
                    self.audioPlayer?.delegate = self.audioDelegate
                    self.audioPlayer?.enableRate = true
                    self.audioPlayer?.rate = 1.0
                    self.audioPlayer?.prepareToPlay()
                    self.audioPlayer?.play()
                } catch {
                    self.speakText(self.currentParagraph?.text ?? "")
                }
            }
        }.resume()
    }

    private func speakText(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.35
        utterance.pitchMultiplier = 0.85
        utterance.volume = 0.9
        AVSpeechSynthesizer().speak(utterance)
    }
}

// MARK: - Preview

#Preview {
    let json = """
    {"id":"1","childId":"c1","storyTitle":"Test","storyContent":"Once upon a time.\\n\\nA little fox walked.\\n\\nShe fell asleep.","parentPrompt":"Loves foxes","storytellingTone":"calming","initialState":"normal","startTime":"2026-01-01T00:00:00Z","completed":false,"initialDriftScore":0,"finalDriftScore":0,"driftScoreHistory":[],"generatedImages":[],"minigameFrequency":"every_paragraph","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}
    """.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let story = try! decoder.decode(Story.self, from: json)
    return StoryPlaybackView(story: story, onComplete: { _, _ in })
        .environmentObject(VitalsManager())
        .environmentObject(AuthManager())
}
