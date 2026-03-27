import SwiftUI
import Speech
import AVFoundation

// MARK: - VoiceMinigame

/// Mic opens, child speaks. SFSpeechRecognizer checks if what they said
/// matches the target word/sound (case-insensitive, partial match).
struct VoiceMinigame: View {
    let target: String       // e.g. "moo", "three", "circle"
    let hint: String         // e.g. "What sound does a cow make?"
    let onComplete: (MinigameResult) -> Void

    @StateObject private var recognizer = SpeechRecognizer()
    @State private var phase: VoicePhase = .waiting
    @State private var transcript = ""
    @State private var resultCorrect: Bool? = nil

    enum VoicePhase { case waiting, listening, processing, done }

    var body: some View {
        VStack(spacing: 28) {
            // Hint label
            Text(hint)
                .font(.custom("Georgia", size: 20))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            // Mic visual
            ZStack {
                // Pulsing rings when listening
                if phase == .listening {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(Color.cyan.opacity(0.4 - Double(i) * 0.12), lineWidth: 2)
                            .frame(width: CGFloat(100 + i * 36), height: CGFloat(100 + i * 36))
                            .scaleEffect(phase == .listening ? 1.15 : 1.0)
                            .animation(
                                .easeInOut(duration: 0.9)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.25),
                                value: phase == .listening
                            )
                    }
                }

                // Result circle
                Circle()
                    .fill(micCircleColor)
                    .frame(width: 100, height: 100)
                    .shadow(color: micCircleColor.opacity(0.5), radius: 16)

                Image(systemName: micIcon)
                    .font(.system(size: 38))
                    .foregroundColor(.white)
            }
            .frame(height: 170)

            // Transcript readout
            if !transcript.isEmpty {
                Text(""\(transcript)"")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 24)
            }

            // Status label
            statusLabel

            // Action button
            actionButton
        }
        .onAppear { recognizer.requestPermission() }
        .onDisappear { recognizer.stop() }
        .onChange(of: recognizer.transcript) { t in
            transcript = t
            if phase == .listening && !t.isEmpty {
                checkAnswer(t)
            }
        }
    }

    // MARK: - Sub-views

    private var micCircleColor: Color {
        switch phase {
        case .waiting:    return Color.white.opacity(0.15)
        case .listening:  return Color.cyan.opacity(0.85)
        case .processing: return Color.orange.opacity(0.8)
        case .done:       return resultCorrect == true ? Color.green.opacity(0.85) : Color.orange.opacity(0.8)
        }
    }

    private var micIcon: String {
        switch phase {
        case .waiting:    return "mic.slash"
        case .listening:  return "mic.fill"
        case .processing: return "waveform"
        case .done:       return resultCorrect == true ? "checkmark" : "arrow.counterclockwise"
        }
    }

    private var statusLabel: some View {
        Group {
            switch phase {
            case .waiting:
                Text("Tap the button and speak!")
                    .foregroundColor(.white.opacity(0.6))
            case .listening:
                Text("I'm listening...")
                    .foregroundColor(.cyan)
            case .processing:
                Text("Let me check...")
                    .foregroundColor(.orange)
            case .done:
                if resultCorrect == true {
                    Text("Amazing! That's right! 🎉")
                        .foregroundColor(.green)
                        .fontWeight(.bold)
                } else {
                    Text("Good try! Let's move on.")
                        .foregroundColor(.orange)
                }
            }
        }
        .font(.system(size: 16, weight: .medium))
    }

    private var actionButton: some View {
        Group {
            if phase == .waiting || phase == .done {
                Button {
                    if phase == .done {
                        finishResult()
                    } else {
                        startListening()
                    }
                } label: {
                    Text(phase == .done ? "Continue" : "Start Talking")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.cyan)
                        .cornerRadius(14)
                }
            } else if phase == .listening {
                Button { stopListening() } label: {
                    Text("Done Talking")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.yellow)
                        .cornerRadius(14)
                }
            }
        }
    }

    // MARK: - Logic

    private func startListening() {
        phase = .listening
        transcript = ""
        recognizer.start()
        // Auto-stop after 8 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if phase == .listening { stopListening() }
        }
    }

    private func stopListening() {
        recognizer.stop()
        phase = .processing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            checkAnswer(transcript)
        }
    }

    private func checkAnswer(_ spoken: String) {
        let cleaned = spoken.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let targetCleaned = target.lowercased()

        // Partial match: spoken contains target or target contains spoken
        let correct = cleaned.contains(targetCleaned) || targetCleaned.contains(cleaned) && !cleaned.isEmpty

        resultCorrect = correct
        phase = .done
        recognizer.stop()
    }

    private func finishResult() {
        onComplete(MinigameResult(
            type: .voice,
            completed: true,
            correct: resultCorrect,
            skipped: false,
            responseData: transcript
        ))
    }
}

// MARK: - SpeechRecognizer

@MainActor
class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }

    func start() {
        transcript = ""
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let request = recognitionRequest else { return }
            request.shouldReportPartialResults = true

            let inputNode = audioEngine.inputNode
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, _ in
                self?.transcript = result?.bestTranscription.formattedString ?? ""
            }

            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("SpeechRecognizer error: \(error)")
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
