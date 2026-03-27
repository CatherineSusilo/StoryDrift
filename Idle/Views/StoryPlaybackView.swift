import SwiftUI
import AVFoundation

struct StoryPlaybackView: View {
    @EnvironmentObject var vitalsManager: VitalsManager
    let story: Story
    let onComplete: ([Double], TimeInterval) -> Void
    
    @State private var currentParagraphIndex = 0
    @State private var isPlaying = true
    @State private var elapsedTime: TimeInterval = 0
    @State private var showMenu = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var timer: Timer?
    @State private var driftHistory: [Double] = []
    @State private var paragraphElapsed: TimeInterval = 0  // seconds on current paragraph

    // SmartSpectra vitals tracker — one instance per playback session
    @StateObject private var vitalsTracker = StoryVitalsTracker()

    /// Minimum seconds each paragraph is shown before auto-advancing.
    /// Distributes the full target duration evenly across all paragraphs.
    private var minSecondsPerParagraph: TimeInterval {
        let targetSeconds = TimeInterval((story.targetDuration ?? 15) * 60)
        let count = max(1, story.paragraphs.count)
        return targetSeconds / TimeInterval(count)
    }
    
    private var currentParagraph: StoryParagraph? {
        guard currentParagraphIndex < story.paragraphs.count else { return nil }
        return story.paragraphs[currentParagraphIndex]
    }
    
    private var currentImage: String? {
        let index = min(currentParagraphIndex, story.images.count - 1)
        return story.images.indices.contains(index) ? story.images[index] : story.images.first
    }
    
    private var progress: Double {
        guard !story.paragraphs.isEmpty else { return 0 }
        return Double(currentParagraphIndex) / Double(story.paragraphs.count)
    }
    
    var body: some View {
        ZStack {
            // Background Image
            if let imageURL = currentImage,
               let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.purple.opacity(0.3)
                }
                .ignoresSafeArea()
                .overlay(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0.6),
                            Color.black.opacity(0.3),
                            Color.black.opacity(0.7)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )
            } else {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.15),
                        Color(red: 0.15, green: 0.05, blue: 0.25)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }

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
        vitalsManager.startMonitoring(childId: story.childId)

        // Start SmartSpectra continuous vitals tracking
        vitalsTracker.startTracking(
            storyId: story.id,
            childId: story.childId,
            vitalsManager: vitalsManager
        )

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if isPlaying {
                elapsedTime += 1
                paragraphElapsed += 1
                driftHistory.append(vitalsManager.driftScore)

                // Sleep detected
                if vitalsManager.driftScore >= 90 {
                    completeStory()
                    return
                }

                // Auto-advance when the paragraph has been shown for its minimum time
                if paragraphElapsed >= minSecondsPerParagraph {
                    paragraphElapsed = 0
                    nextParagraph()
                }

                // DEBUG: end after 2 min when using debug prompt
                #if DEBUG
                if story.parentPrompt.hasPrefix("DEBUG_2MIN:") && elapsedTime >= 120 {
                    completeStory()
                }
                #endif
            }
        }

        playCurrentParagraph()
    }

    private func stopStory() {
        timer?.invalidate()
        timer = nil
        audioPlayer?.stop()
        vitalsManager.stopMonitoring()

        // Stop SmartSpectra and persist vitals summary
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
        withAnimation {
            currentParagraphIndex += 1
        }

        playCurrentParagraph()
    }
    
    private func playCurrentParagraph() {
        guard let paragraph = currentParagraph else { return }
        
        // If audio URL exists, play it
        if let audioURLString = paragraph.audioUrl,
           let url = URL(string: audioURLString) {
            playAudio(url: url)
        } else {
            // Use text-to-speech as fallback
            speakText(paragraph.text)
        }
    }
    
    private func playAudio(url: URL) {
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { return }
            DispatchQueue.main.async {
                do {
                    self.audioPlayer = try AVAudioPlayer(data: data)
                    self.audioPlayer?.play()
                    // Paragraph advancement is handled by the timer (minSecondsPerParagraph)
                } catch {
                    print("Error playing audio: \(error)")
                    self.speakText(self.currentParagraph?.text ?? "")
                }
            }
        }.resume()
    }
    
    private func speakText(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.4
        utterance.pitchMultiplier = 0.9

        let synthesizer = AVSpeechSynthesizer()
        synthesizer.speak(utterance)
        // Paragraph advancement is handled by the timer (minSecondsPerParagraph)
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
}
