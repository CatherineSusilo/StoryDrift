import SwiftUI
import Speech
import AVFoundation

// MARK: - VoiceMinigame

/// Mic opens, child speaks. SFSpeechRecognizer checks if what they said
/// matches the target word/sound (case-insensitive, partial match).
struct VoiceMinigame: View {
    let target: String
    let hint: String
    let onActivity: () -> Void
    let onComplete: (MinigameResult) -> Void

    @StateObject private var recognizer = SpeechRecognizer()
    @State private var phase: VoicePhase = .waiting
    @State private var transcript = ""
    @State private var resultCorrect: Bool? = nil

    enum VoicePhase { case waiting, listening, processing, done }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 340
            let circleSize: CGFloat = compact ? 64 : 100
            let ringMax: CGFloat    = compact ? 44 : 68

            VStack(spacing: compact ? 8 : 20) {
                // Hint
                Text(hint)
                    .font(.custom("Georgia", size: compact ? 14 : 20))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .lineLimit(2)

                // Mic visual
                ZStack {
                    if phase == .listening {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .stroke(Color.cyan.opacity(0.4 - Double(i) * 0.12), lineWidth: 2)
                                .frame(width: circleSize + CGFloat(i) * ringMax * 0.5,
                                       height: circleSize + CGFloat(i) * ringMax * 0.5)
                                .scaleEffect(phase == .listening ? 1.12 : 1.0)
                                .animation(
                                    .easeInOut(duration: 0.9)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(i) * 0.25),
                                    value: phase == .listening
                                )
                        }
                    }
                    Circle()
                        .fill(micCircleColor)
                        .frame(width: circleSize, height: circleSize)
                        .shadow(color: micCircleColor.opacity(0.5), radius: 12)
                    Image(systemName: micIcon)
                        .font(.system(size: compact ? 24 : 38))
                        .foregroundColor(.white)
                }
                .frame(height: circleSize + (phase == .listening ? ringMax : 0) + 8)

                // Transcript
                if !transcript.isEmpty {
                    Text("\"\(transcript)\"")
                        .font(.system(size: compact ? 13 : 17, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 16)
                        .lineLimit(2)
                }

                // Status
                statusLabel(compact: compact)

                // Action button
                actionButton(compact: compact)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear { recognizer.requestPermission() }
        .onDisappear { recognizer.stop() }
        .onChange(of: recognizer.transcript) { t in
            transcript = t
            if phase == .listening && !t.isEmpty { checkAnswer(t) }
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

    private func statusLabel(compact: Bool) -> some View {
        Group {
            switch phase {
            case .waiting:    Text("Tap the button and speak!").foregroundColor(.white.opacity(0.6))
            case .listening:  Text("I'm listening...").foregroundColor(.cyan)
            case .processing: Text("Let me check...").foregroundColor(.orange)
            case .done:
                if resultCorrect == true {
                    Text("Amazing! That's right! 🎉").foregroundColor(.green).fontWeight(.bold)
                } else {
                    Text("Good try! Let's move on.").foregroundColor(.orange)
                }
            }
        }
        .font(.system(size: compact ? 13 : 16, weight: .medium))
    }

    private func actionButton(compact: Bool) -> some View {
        Group {
            if phase == .waiting || phase == .done {
                Button {
                    onActivity()
                    phase == .done ? finishResult() : startListening()
                } label: {
                    Text(phase == .done ? "Continue" : "Start Talking")
                        .font(.system(size: compact ? 14 : 17, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compact ? 8 : 12)
                        .background(Color.cyan)
                        .cornerRadius(12)
                }
            } else if phase == .listening {
                Button {
                    onActivity()
                    stopListening()
                } label: {
                    Text("Done Talking")
                        .font(.system(size: compact ? 14 : 17, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compact ? 8 : 12)
                        .background(Color.yellow)
                        .cornerRadius(12)
                }
            }
        }
    }

    // MARK: - Logic

    private func startListening() {
        phase = .listening
        transcript = ""
        recognizer.start()
        // Auto-stop after 5 seconds to prevent nw_read network timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if self.phase == .listening { self.stopListening() }
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
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("[VoiceMinigame] SFSpeechRecognizer unavailable")
            return
        }

        stop() // ensure clean state

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let request = recognitionRequest else { return }
            request.shouldReportPartialResults = true
            // Limit on-device to avoid network timeout — no server round-trip needed
            if #available(iOS 17, *) {
                request.addsPunctuation = false
            }

            let inputNode = audioEngine.inputNode
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let result = result {
                    DispatchQueue.main.async { self?.transcript = result.bestTranscription.formattedString }
                }
                if error != nil || result?.isFinal == true {
                    DispatchQueue.main.async { self?.transcript = self?.transcript ?? "" }
                }
            }

            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("[VoiceMinigame] Start error: \(error)")
        }
    }

    func stop() {
        guard audioEngine.isRunning else { return }
        audioEngine.stop()
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask?.finish()
        recognitionRequest = nil
        recognitionTask = nil
        // Deactivate with delay to let the socket close cleanly (prevents nw_read timeout log)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
