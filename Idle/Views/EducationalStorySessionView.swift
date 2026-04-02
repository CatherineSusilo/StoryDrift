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
    let minigameFrequency: MinigameFrequency
    let onComplete: (EducationalSummary) -> Void

    @Environment(\.dismiss) private var dismiss
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
    
    // Minigame drawing results to save to collection after story
    @State private var minigameDrawings: [(base64: String, timestamp: Date)] = []

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
        StoryImageView.educational(imageUrl: currentImageUrl, engagementScore: engagementScore)
    }

    // MARK: - Loading overlay

    private var loadingOverlay: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
            Text("Preparing \"\(lesson.name)\"…")
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
            // Close button
            Button {
                tearDown()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(10)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }

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
            // Check if this is a curriculum lesson
            let curriculumLessonId = UserDefaults.standard.string(forKey: "pendingCurriculumLessonId")
            UserDefaults.standard.removeObject(forKey: "pendingCurriculumLessonId")
            
            var body: [String: Any] = [
                "mode": "educational",
                "childProfile": [
                    "childId": child.id,
                    "name": child.name,
                    "age": child.age,
                    "favoriteCharacter": child.name,
                ],
                "minigameFrequency": minigameFrequency.rawValue,
            ]
            
            // If we have a curriculum lesson ID, use it (backend will auto-resolve lesson data)
            // Otherwise, use the legacy lesson name/description
            if let curriculumId = curriculumLessonId {
                body["curriculumLessonId"] = curriculumId
                print("📚 Starting curriculum lesson: \(curriculumId)")
            } else {
                body["lessonName"] = lesson.name
                body["lessonDescription"] = lesson.description
            }

            let data = try await APIService.shared.post(
                path: "/api/story-session/start",
                body: body,
                token: token
            )
            let resp = try JSONDecoder().decode(SessionStartResponse.self, from: data)
            sessionId = resp.sessionId
            let useSynthetic = !vitalsManager.isCameraEnabled
            vitalsManager.startMonitoring(childId: child.id, useSynthetic: useSynthetic)
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

        let cameraEnabled = vitalsManager.isCameraEnabled && vitalsManager.signalQuality > 20
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
        if let audioUrl = resp.audioUrl, !audioUrl.isEmpty {
            playAudio(url: audioUrl)
        }

        // Session complete
        if resp.sessionComplete {
            tickTimer?.invalidate()
            vitalsManager.stopMonitoring()
            
            // Save any collected drawings to the drawings collection
            saveMinigameDrawings()
            
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

        print("🎮 Minigame completed: type=\(result.type), completed=\(result.completed), hasData=\(result.responseData != nil)")

        // Collect drawing results for later saving to collection
        if result.type == .drawing {
            if result.completed {
                if let base64 = result.responseData {
                    let previewLength = min(base64.count, 50)
                    print("📝 Drawing base64 preview: \(String(base64.prefix(previewLength)))... (total: \(base64.count) chars)")
                    
                    // Validate base64 can be decoded
                    if let testData = Data(base64Encoded: base64) {
                        print("✅ Base64 decodes to \(testData.count) bytes")
                        if UIImage(data: testData) != nil {
                            print("✅ Data creates valid UIImage")
                        } else {
                            print("⚠️ Data doesn't create valid UIImage")
                        }
                    } else {
                        print("❌ Base64 string cannot be decoded!")
                    }
                    
                    minigameDrawings.append((base64: base64, timestamp: Date()))
                    print("📝 Collected drawing #\(minigameDrawings.count) from minigame")
                } else {
                    print("⚠️ Drawing completed but no responseData!")
                }
            } else {
                print("ℹ️ Drawing minigame not completed (skipped)")
            }
        }

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
    
    // MARK: - Save drawings to collection
    
    @MainActor
    private func saveMinigameDrawings() {
        guard !minigameDrawings.isEmpty else {
            print("ℹ️ No drawings to save")
            return
        }
        
        print("💾 Saving \(minigameDrawings.count) drawings to collection for child \(child.id)")
        
        // Load existing drawings for this child
        let drawingsKey = "drawings_\(child.id)"
        var existingDrawings: [ChildDrawing] = []
        
        // Load existing drawings with error handling
        if let data = UserDefaults.standard.data(forKey: drawingsKey) {
            do {
                existingDrawings = try JSONDecoder().decode([ChildDrawing].self, from: data)
                print("📂 Loaded \(existingDrawings.count) existing drawings")
            } catch {
                print("⚠️ Failed to decode existing drawings: \(error)")
                // Continue with empty array - don't lose new drawings
            }
        } else {
            print("📂 No existing drawings for this child")
        }
        
        // Convert base64 drawings to ChildDrawing objects
        for (index, drawing) in minigameDrawings.enumerated() {
            // Decode base64 to PNG data
            guard let imageData = Data(base64Encoded: drawing.base64) else {
                print("❌ Failed to decode drawing #\(index + 1) - invalid base64")
                continue
            }
            
            // Verify we got valid PNG data
            guard UIImage(data: imageData) != nil else {
                print("❌ Failed to create image from data for drawing #\(index + 1)")
                continue
            }
            
            // Create drawing with timestamp-based name
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let timestamp = formatter.string(from: drawing.timestamp)
            let name = "\(lesson.emoji) \(lesson.name) - \(timestamp)"
            
            let childDrawing = ChildDrawing(
                name: name,
                imageData: imageData,
                uploadedAt: drawing.timestamp
            )
            
            existingDrawings.append(childDrawing)
            print("✅ Added drawing: \(name) (size: \(imageData.count) bytes)")
        }
        
        // Save back to UserDefaults with error handling
        do {
            let encoded = try JSONEncoder().encode(existingDrawings)
            UserDefaults.standard.set(encoded, forKey: drawingsKey)
            
            // CRITICAL: Force synchronization to disk
            let synced = UserDefaults.standard.synchronize()
            if synced {
                print("💾 Successfully saved and synchronized \(minigameDrawings.count) new drawings")
                print("📊 Total drawings for child: \(existingDrawings.count)")
            } else {
                print("⚠️ synchronize() returned false - data may not be persisted")
            }
            
            // Verify the save by reading back
            if let verifyData = UserDefaults.standard.data(forKey: drawingsKey),
               let verifyDecoded = try? JSONDecoder().decode([ChildDrawing].self, from: verifyData) {
                print("✅ Verified: \(verifyDecoded.count) drawings in UserDefaults")
                
                // Sync to MongoDB in background
                Task {
                    await syncMinigameDrawingsToBackend(drawings: Array(existingDrawings.suffix(minigameDrawings.count)))
                }
            } else {
                print("❌ Verification failed - drawings may not be readable")
            }
            
        } catch {
            print("❌ Failed to encode drawings: \(error)")
        }
    }
    
    // MARK: - Backend Sync
    
    /// Sync newly saved minigame drawings to MongoDB with cloud storage
    @MainActor
    private func syncMinigameDrawingsToBackend(drawings: [ChildDrawing]) async {
        guard let token = authManager.accessToken else {
            print("⚠️ No auth token - skipping backend sync")
            return
        }
        
        guard !drawings.isEmpty else { return }
        
        print("☁️ Syncing \(drawings.count) minigame drawings to MongoDB with cloud upload...")
        
        // Convert to upload requests - backend will upload to R2
        let uploadRequests = drawings.compactMap { drawing -> DrawingUploadRequest? in
            guard let imageData = drawing.imageData else { return nil }
            return DrawingUploadRequest(
                childId: child.id,
                name: drawing.name,
                imageData: imageData.base64EncodedString(),
                uploadedAt: drawing.uploadedAt,
                source: "minigame",
                lessonName: lesson.name,
                lessonEmoji: lesson.emoji
            )
        }
        
        do {
            let result = try await APIService.shared.uploadDrawingsBatch(
                childId: child.id,
                drawings: uploadRequests,
                token: token
            )
            print("✅ MongoDB cloud sync complete: \(result.success) uploaded to R2, \(result.failed) failed")
            if let errors = result.errors, !errors.isEmpty {
                print("⚠️ Sync errors: \(errors.joined(separator: ", "))")
            }
        } catch {
            print("❌ Backend cloud sync failed: \(error)")
        }
    }

    private func tearDown() {
        tickTimer?.invalidate()
        audioPlayer?.stop()
        vitalsManager.stopMonitoring()
        
        // Save any collected drawings even if story wasn't completed
        if !minigameDrawings.isEmpty {
            print("📝 Story ended early - saving \(minigameDrawings.count) drawings")
            saveMinigameDrawings()
        }

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

    private func playAudio(url: String) {
        guard !url.isEmpty else { return }
        
        // Handle both R2 URLs (https://...) and legacy local URLs (/images/...)
        let fullUrl: URL?
        if url.hasPrefix("http") {
            fullUrl = URL(string: url)
        } else {
            fullUrl = URL(string: "\(APIService.baseURL)\(url)")
        }
        
        guard let audioUrl = fullUrl else {
            print("⚠️ Invalid audio URL: \(url)")
            return
        }
        
        DispatchQueue.main.async {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [])
                try session.setActive(true)
                
                // Fetch audio data from URL
                URLSession.shared.dataTask(with: audioUrl) { data, _, error in
                    guard let data = data, error == nil else {
                        print("⚠️ Failed to fetch audio from \(audioUrl): \(error?.localizedDescription ?? "unknown error")")
                        return
                    }
                    
                    DispatchQueue.main.async {
                        do {
                            self.audioPlayer = try AVAudioPlayer(data: data)
                            self.audioPlayer?.prepareToPlay()
                            self.audioPlayer?.play()
                        } catch {
                            print("⚠️ Audio playback error: \(error)")
                        }
                    }
                }.resume()
            } catch {
                print("⚠️ AVAudioSession error: \(error)")
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
