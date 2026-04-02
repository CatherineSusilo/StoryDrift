import SwiftUI
import AVFoundation

// MARK: - StoryReplayView
//
// Archive replay of a completed story.
// • No minigames
// • No vitals monitoring / drift tracking
// • Loads images from the cloud (story.images / imageJobId polling)
// • Loads audio from story.audioUrls (paragraph.audioUrl)

struct StoryReplayView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    let story: Story

    // Playback state
    @State private var currentParagraphIndex = 0
    @State private var isPlaying = true
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var showMenu = false

    // Audio
    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioDelegate = AudioFinishDelegate()
    @State private var ttsDelegate = TTSFinishDelegate()
    private let synthesizer = AVSpeechSynthesizer()

    // Images (polled from cloud if imageJobId is present)
    @State private var paragraphImages: [String] = []
    @State private var imagePollingTimer: Timer?

    // MARK: - Computed

    private var currentParagraph: StoryParagraph? {
        guard currentParagraphIndex < story.paragraphs.count else { return nil }
        return story.paragraphs[currentParagraphIndex]
    }

    private var currentImage: String? {
        let idx = currentParagraphIndex
        // Use polled image for this paragraph if available
        if paragraphImages.indices.contains(idx), !paragraphImages[idx].isEmpty {
            return paragraphImages[idx]
        }
        // Fall back to story.images only at the exact same index (no clamping)
        if story.images.indices.contains(idx), !story.images[idx].isEmpty {
            return story.images[idx]
        }
        return nil
    }

    private var progress: Double {
        guard !story.paragraphs.isEmpty else { return 0 }
        return Double(currentParagraphIndex) / Double(story.paragraphs.count)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let safeBottom = geo.safeAreaInsets.bottom
            let safeTop    = geo.safeAreaInsets.top
            let safeLeft   = geo.safeAreaInsets.leading
            let safeRight  = geo.safeAreaInsets.trailing
            let btnPad: CGFloat = 16

            ZStack {
                // ── Full-screen background ───────────────────────────────────
                StoryImageView.bedtime(imageUrl: currentImage, driftScore: Int(progress * 100))
                    .frame(width: geo.size.width + safeLeft + safeRight,
                           height: geo.size.height + safeTop + safeBottom)
                    .offset(x: -safeLeft, y: -safeTop)
                    .id(currentParagraphIndex)
                    .zIndex(0)

                // ── Timer — top right ────────────────────────────────────────
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

                // ── "Replaying" badge — top left ─────────────────────────────
                VStack {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                            Text("replay")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .padding(.top, max(safeTop, 12))
                        .padding(.leading, max(safeLeft, 12) + btnPad)
                        Spacer()
                    }
                    Spacer()
                }
                .zIndex(1)

                // ── Caption — bottom centre ──────────────────────────────────
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
                    Color.clear.frame(height: safeBottom + 52)
                }
                .zIndex(1)

                // ── Bottom-left: menu button ─────────────────────────────────
                VStack {
                    Spacer()
                    HStack {
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) { showMenu.toggle() }
                        }) {
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

                // ── Menu sheet (bottom-up) ───────────────────────────────────
                if showMenu {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) { showMenu = false }
                        }
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

                            menuButton(icon: "backward.fill", label: "Previous Paragraph",
                                       color: .white) {
                                prevParagraph()
                                withAnimation { showMenu = false }
                            }
                            Divider().background(Color.white.opacity(0.15))

                            menuButton(icon: "forward.fill", label: "Next Paragraph",
                                       color: .white) {
                                nextParagraph()
                                withAnimation { showMenu = false }
                            }
                            Divider().background(Color.white.opacity(0.15))

                            menuButton(icon: "xmark.circle.fill", label: "Close Replay",
                                       color: Color(red: 1, green: 0.35, blue: 0.35)) {
                                showMenu = false
                                stopStory()
                                dismiss()
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
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showMenu)
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
        // Seed paragraph images from already-stored URLs
        paragraphImages = Array(repeating: "", count: story.paragraphs.count)
        for (i, url) in story.images.enumerated() where i < paragraphImages.count {
            paragraphImages[i] = url
        }

        // Poll cloud if a background image job was running when story was saved
        if let jobId = story.imageJobId, !jobId.isEmpty {
            startImagePolling(jobId: jobId)
        }

        // Elapsed-time ticker
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard self.isPlaying else { return }
            self.elapsedTime += 1
        }

        playCurrentParagraph()
    }

    private func stopStory() {
        timer?.invalidate(); timer = nil
        stopImagePolling()
        audioPlayer?.stop()
        audioPlayer = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func togglePlayback() {
        isPlaying.toggle()
        if isPlaying { audioPlayer?.play() } else { audioPlayer?.pause() }
    }

    private func nextParagraph() {
        guard currentParagraphIndex < story.paragraphs.count - 1 else {
            // End of story — dismiss
            stopStory()
            dismiss()
            return
        }
        withAnimation { currentParagraphIndex += 1 }
        playCurrentParagraph()
    }

    private func prevParagraph() {
        guard currentParagraphIndex > 0 else { return }
        withAnimation { currentParagraphIndex -= 1 }
        playCurrentParagraph()
    }

    /// Called by AudioFinishDelegate when a paragraph's audio finishes.
    private func audioDidFinish() {
        guard isPlaying else { return }
        nextParagraph()
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    // MARK: - Image polling

    private func startImagePolling(jobId: String) {
        let token = authManager.accessToken ?? UserDefaults.standard.string(forKey: "accessToken") ?? ""
        guard !token.isEmpty else { return }
        fetchImages(jobId: jobId, token: token)
        imagePollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.fetchImages(jobId: jobId, token: token)
        }
    }

    private func fetchImages(jobId: String, token: String) {
        Task {
            guard let url = URL(string: "\(APIService.baseURL)/api/generate/story-images/\(jobId)") else { return }
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let images = json["images"] as? [String] else { return }
            await MainActor.run {
                for (i, imgUrl) in images.enumerated()
                    where i < self.paragraphImages.count && !imgUrl.isEmpty {
                    if self.paragraphImages[i].isEmpty { self.paragraphImages[i] = imgUrl }
                }
                if json["complete"] as? Bool == true { self.stopImagePolling() }
            }
        }
    }

    private func stopImagePolling() {
        imagePollingTimer?.invalidate()
        imagePollingTimer = nil
    }

    // MARK: - Audio

    private func playCurrentParagraph() {
        audioPlayer?.stop()
        guard let paragraph = currentParagraph else { return }

        if let rawUrl = paragraph.audioUrl, !rawUrl.isEmpty {
            let fullUrl = rawUrl.hasPrefix("http")
                ? URL(string: rawUrl)
                : URL(string: "\(APIService.baseURL)\(rawUrl)")
            if let url = fullUrl {
                playAudio(url: url)
                return
            }
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
        synthesizer.stopSpeaking(at: .immediate)
        ttsDelegate.onFinish = { self.audioDidFinish() }
        synthesizer.delegate = ttsDelegate
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.35
        utterance.pitchMultiplier = 0.85
        utterance.volume = 0.9
        synthesizer.speak(utterance)
    }
}

// MARK: - Preview

#Preview {
    let json = """
    {"id":"1","childId":"c1","storyTitle":"The Fox and the Moon","storyContent":"Once upon a time, a little fox looked at the moon.\\n\\nShe wondered if the moon was her friend.\\n\\nSlowly her eyes grew heavy and she drifted to sleep.","parentPrompt":"Loves foxes","storytellingTone":"calming","initialState":"normal","startTime":"2026-01-01T00:00:00Z","completed":true,"initialDriftScore":0,"finalDriftScore":80,"driftScoreHistory":[20,50,80],"generatedImages":[],"minigameFrequency":"none","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}
    """.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let story = try! decoder.decode(Story.self, from: json)
    return StoryReplayView(story: story)
        .environmentObject(AuthManager())
}
