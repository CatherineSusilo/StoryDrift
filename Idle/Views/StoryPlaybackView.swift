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

    // SmartSpectra vitals tracker — one instance per playback session
    @StateObject private var vitalsTracker = StoryVitalsTracker()
    
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
                    Button(action: { showMenu = true }) {
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
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.3))
                        )
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
                DriftMeterView(
                    driftScore: vitalsManager.driftScore,
                    isCompact: true
                )
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
        }
        .onAppear {
            startStory()
        }
        .onDisappear {
            stopStory()
        }
        .confirmationDialog("Story Menu", isPresented: $showMenu) {
            Button(isPlaying ? "Pause" : "Resume") {
                togglePlayback()
            }
            Button("Next Paragraph") {
                nextParagraph()
            }
            Button("End Story", role: .destructive) {
                completeStory()
            }
            Button("Cancel", role: .cancel) {}
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
                driftHistory.append(vitalsManager.driftScore)

                // Check if child is asleep (drift > 90%)
                if vitalsManager.driftScore >= 90 {
                    completeStory()
                }

                // MARK: - ⚠️ DEBUG ONLY — remove before release
                #if DEBUG
                if story.parentPrompt.hasPrefix("DEBUG_2MIN:") && elapsedTime >= 120 {
                    completeStory()
                }
                #endif
                // END DEBUG
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
        // Download and play audio
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { return }
            
            DispatchQueue.main.async {
                do {
                    audioPlayer = try AVAudioPlayer(data: data)
                    audioPlayer?.delegate = AudioPlayerDelegate(onFinish: nextParagraph)
                    audioPlayer?.play()
                } catch {
                    print("Error playing audio: \(error)")
                    speakText(currentParagraph?.text ?? "")
                }
            }
        }.resume()
    }
    
    private func speakText(_ text: String) {
        // Use AVSpeechSynthesizer for text-to-speech
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.4 // Slower for bedtime
        utterance.pitchMultiplier = 0.9
        
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.speak(utterance)
        
        // Auto-advance after speaking
        let estimatedDuration = Double(text.count) / 10 // ~10 chars per second
        DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration) {
            if isPlaying {
                nextParagraph()
            }
        }
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
