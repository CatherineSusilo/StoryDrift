import Foundation
import AVFoundation

class AudioService: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    
    private var audioPlayer: AVAudioPlayer?
    private var synthesizer = AVSpeechSynthesizer()
    private var audioSession = AVAudioSession.sharedInstance()
    
    override init() {
        super.init()
        setupAudioSession()
        synthesizer.delegate = self
    }
    
    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    // MARK: - Audio Playback
    
    func playAudioData(_ data: Data) async throws {
        try await MainActor.run {
            do {
                audioPlayer = try AVAudioPlayer(data: data)
                audioPlayer?.delegate = self
                audioPlayer?.prepareToPlay()
                
                duration = audioPlayer?.duration ?? 0
                audioPlayer?.play()
                isPlaying = true
                
                startMonitoringPlayback()
            } catch {
                throw AudioServiceError.playbackFailed
            }
        }
    }
    
    // MARK: - Text-to-Speech Fallback
    
    func speakText(_ text: String, rate: Float = 0.5) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        synthesizer.speak(utterance)
        isPlaying = true
    }
    
    // MARK: - Playback Control
    
    func pause() {
        if let player = audioPlayer, player.isPlaying {
            player.pause()
            isPlaying = false
        } else if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
            isPlaying = false
        }
    }
    
    func resume() {
        if let player = audioPlayer {
            player.play()
            isPlaying = true
        } else if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isPlaying = true
        }
    }
    
    func stop() {
        audioPlayer?.stop()
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        currentTime = 0
    }
    
    // MARK: - Monitoring
    
    private func startMonitoringPlayback() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            if let player = self.audioPlayer, player.isPlaying {
                self.currentTime = player.currentTime
            } else if !self.isPlaying {
                timer.invalidate()
            }
        }
    }
    
    // MARK: - Voice Selection
    
    static let availableVoices: [VoiceOption] = [
        VoiceOption(id: "EXAVITQu4vr4xnSDxMaL", name: "Sarah", description: "Warm and soothing"),
        VoiceOption(id: "21m00Tcm4TlvDq8ikWAM", name: "Rachel", description: "Gentle and calm"),
        VoiceOption(id: "AZnzlk1XvdvUeBnXmlld", name: "Domi", description: "Energetic and fun"),
        VoiceOption(id: "ErXwobaYiN019PkySvjV", name: "Antoni", description: "Deep and reassuring"),
        VoiceOption(id: "MF3mGyEYCl7XYWbV9V6O", name: "Elli", description: "Sweet and melodic")
    ]
    
}

// MARK: - AVAudioPlayerDelegate

extension AudioService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = 0
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("Audio decode error: \(error?.localizedDescription ?? "Unknown")")
        isPlaying = false
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension AudioService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isPlaying = false
    }
}

// MARK: - Models

struct VoiceOption: Identifiable {
    let id: String
    let name: String
    let description: String
}

enum AudioServiceError: Error {
    case apiError
    case playbackFailed
    case invalidData
}
