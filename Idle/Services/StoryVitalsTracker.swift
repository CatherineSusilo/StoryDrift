import Foundation
import Combine
import SwiftUI

#if canImport(SmartSpectraSwiftSDK)
import SmartSpectraSwiftSDK
#endif

// MARK: - StoryVitalsSnapshot
/// A single vitals reading captured at one point during a story session.
struct StoryVitalsSnapshot: Codable, Identifiable {
    var id: String = UUID().uuidString
    let timestamp: Date
    let heartRate: Double       // bpm; 0 = not yet measured
    let breathingRate: Double   // breaths/min; 0 = not yet measured
    let confidence: Float       // 0–1 from SmartSpectra

    static var empty: StoryVitalsSnapshot {
        StoryVitalsSnapshot(timestamp: Date(), heartRate: 0, breathingRate: 0, confidence: 0)
    }
}

// MARK: - StoryVitalsSummary
/// Computed summary stored alongside a completed story.
struct StoryVitalsSummary: Codable {
    let storyId: String
    let childId: String
    let avgHeartRate: Double
    let avgBreathingRate: Double
    let minHeartRate: Double
    let maxHeartRate: Double
    let snapshots: [StoryVitalsSnapshot]

    static func compute(storyId: String, childId: String, snapshots: [StoryVitalsSnapshot]) -> StoryVitalsSummary {
        let hrValues = snapshots.map(\.heartRate).filter { $0 > 0 }
        let brValues = snapshots.map(\.breathingRate).filter { $0 > 0 }
        return StoryVitalsSummary(
            storyId: storyId,
            childId: childId,
            avgHeartRate: hrValues.isEmpty ? 0 : hrValues.reduce(0, +) / Double(hrValues.count),
            avgBreathingRate: brValues.isEmpty ? 0 : brValues.reduce(0, +) / Double(brValues.count),
            minHeartRate: hrValues.min() ?? 0,
            maxHeartRate: hrValues.max() ?? 0,
            snapshots: snapshots
        )
    }
}

// MARK: - StoryVitalsStore
/// Persists StoryVitalsSummary objects locally using UserDefaults.
class StoryVitalsStore {
    static let shared = StoryVitalsStore()
    private let key = "storyVitalsSummaries_v1"

    func save(_ summary: StoryVitalsSummary) {
        var all = loadAll()
        all.removeAll { $0.storyId == summary.storyId }
        all.append(summary)
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Returns all summaries for a given childId, newest first.
    func summaries(for childId: String) -> [StoryVitalsSummary] {
        loadAll()
            .filter { $0.childId == childId }
            .sorted { $0.snapshots.first?.timestamp ?? .distantPast > $1.snapshots.first?.timestamp ?? .distantPast }
    }

    private func loadAll() -> [StoryVitalsSummary] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([StoryVitalsSummary].self, from: data)
        else { return [] }
        return decoded
    }
}

// MARK: - StoryVitalsTracker
/// Wraps SmartSpectra in continuous headless mode during a story session.
/// Call startTracking() when the story begins playing and stopTracking() when it ends.
/// Works identically for normal storytime and the DEBUG 2-minute mode.
///
/// **Local On-Device Operation:**
/// SmartSpectra SDK runs entirely on-device using the phone's camera and processors.
/// No USB connection is required — the SDK continues working even when unplugged.
/// USB is only needed for Xcode debugging; the app and vitals tracking work independently.
///
/// When `cameraEnabled` is false, the tracker switches to synthetic drift mode,
/// which provides realistic simulated vitals for testing or privacy-focused scenarios.
class StoryVitalsTracker: ObservableObject {
    static let shared = StoryVitalsTracker()

    @Published var currentHeartRate: Double = 0
    @Published var currentBreathingRate: Double = 0
    @Published var isTracking: Bool = false
    @Published var statusHint: String = "Not started"

    private var snapshots: [StoryVitalsSnapshot] = []
    private var snapshotTimer: Timer?
    private var storyId: String?
    private var childId: String?
    private var cancellables = Set<AnyCancellable>()
    /// Tracks whether the SmartSpectra SDK was actually started this session.
    private var sdkStarted = false

    // MARK: - Eye tracking state (fed from SmartSpectra edgeMetrics)
    /// Rolling window of blink timestamps used to compute blink rate (blinks/min).
    private var blinkTimestamps: [Date] = []
    /// Whether the eyes were detected as closed on the last frame (for blink edge detection).
    private var eyesPreviouslyClosed: Bool = false
    /// Smoothed eye openness ratio (0 = closed, 1 = fully open), EMA-filtered.
    private var smoothedEyeOpenness: Double = 1.0
    /// Computed drowsiness score 0–1 forwarded to VitalsManager.
    @Published var eyeDrowsinessScore: Double = 0

#if canImport(SmartSpectraSwiftSDK)
    private lazy var sdk = SmartSpectraSwiftSDK.shared
    private lazy var processor = SmartSpectraVitalsProcessor.shared
#endif

    // MARK: - Start

    /// Call this the moment the story begins playing (normal or debug mode).
    /// Pass `cameraEnabled: false` to skip all SmartSpectra SDK calls (synthetic drift mode).
    func startTracking(storyId: String, childId: String, vitalsManager: VitalsManager, cameraEnabled: Bool = true) {
        guard !isTracking else { return }

        self.storyId = storyId
        self.childId = childId
        self.snapshots = []
        self.isTracking = true
        self.sdkStarted = false

        // Always cancel any lingering Combine subscriptions from a prior session
        // BEFORE the cameraEnabled check so old sdk.$metricsBuffer / $edgeMetrics
        // sinks are torn down even when switching camera off mid-use.
        cancellables.removeAll()

#if canImport(SmartSpectraSwiftSDK)
        guard cameraEnabled else {
            statusHint = "Camera disabled — using synthetic drift"
            print("[StoryVitalsTracker] ℹ️  Camera disabled, stopping any leftover SDK session.")
            // Stop any lingering SDK session asynchronously so the graph tears down cleanly
            processor.stopRecording()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
                self.processor.stopProcessing()
            }
            // Start snapshot timer for vitals history recording
            snapshotTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                self?.recordSnapshot()
            }
            return
        }

        guard let apiKey = Secrets.smartSpectraAPIKey else {
            statusHint = "SmartSpectra API key not configured"
            print("[StoryVitalsTracker] ⚠️  Set SMARTSPECTRA_API_KEY in Config.xcconfig to enable vitals tracking.")
            isTracking = false
            return
        }

        // Configure SDK for continuous background monitoring
        sdk.setApiKey(apiKey)
        sdk.setSmartSpectraMode(.continuous)
        sdk.setCameraPosition(.front)
        sdk.setRecordingDelay(0)              // no countdown — start immediately
        sdk.setImageOutputEnabled(false)      // disable camera preview output for performance

        statusHint = "Starting camera…"
        print("[StoryVitalsTracker] ▶️  Configuring SDK for local on-device operation")
        print("[StoryVitalsTracker] 📱 SDK runs entirely on-device — USB connection not required")
        print("[StoryVitalsTracker] ⚙️  Mode: continuous, camera: front, story: \(storyId)")

        // Always stop any lingering session BEFORE starting a new one.
        // stopRecording/stopProcessing are internally async (MediaPipe graph teardown).
        // We must wait for the graph to fully shut down before calling startProcessing()
        // otherwise packets arrive before StartRun() completes → CalculatorGraph error.
        processor.stopRecording()
        processor.stopProcessing()

        // Delay long enough for the MediaPipe graph to complete teardown (~500 ms is sufficient).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.isTracking else { return }
            self.processor.startProcessing()
            self.processor.startRecording()
            self.sdkStarted = true
            self.statusHint = self.processor.statusHint
            print("[StoryVitalsTracker] ▶️  SDK started — continuous mode")
        }

        // Observe metrics buffer — fires whenever SmartSpectra produces new measurements
        sdk.$metricsBuffer
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak vitalsManager] buffer in
                guard let self, let buffer, let vitalsManager else { return }

                // Pull the latest pulse rate measurement
                let hr     = buffer.pulse.rate.last.map { Double($0.value) } ?? 0
                let hrConf = buffer.pulse.rate.last.map { $0.confidence } ?? 0

                // Pull the latest breathing rate measurement
                let br = buffer.breathing.rate.last.map { Double($0.value) } ?? 0

                self.currentHeartRate     = hr
                self.currentBreathingRate = br
                self.statusHint           = self.processor.statusHint

                // Forward live values + eye drowsiness into VitalsManager
                vitalsManager.updateVitals(
                    heartRate: hr,
                    breathingRate: br,
                    signalQuality: Int(hrConf * 100),
                    eyeDrowsiness: self.eyeDrowsinessScore
                )
            }
            .store(in: &cancellables)

        // Observe edgeMetrics for eye-state analysis (blink rate + lid openness)
        // edgeMetrics is published as Metrics? (typealias for Presage_Physiology_Metrics)
        sdk.$edgeMetrics
            .receive(on: DispatchQueue.main)
            .compactMap { $0 as? Metrics }
            .sink { [weak self] edge in
                guard let self else { return }
                self.processEyeMetrics(edge: edge)
            }
            .store(in: &cancellables)

        print("[StoryVitalsTracker] ▶️  Started — continuous mode, story: \(storyId)")
#else
        statusHint = "SmartSpectra SDK not linked"
        print("[StoryVitalsTracker] ⚠️  SmartSpectraSwiftSDK not found. Add the package via File → Add Package Dependencies in Xcode.")
#endif

        // Snapshot every 10 seconds regardless of SDK availability
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.recordSnapshot()
        }
    }

    // MARK: - Stop

    /// Call this when the story finishes or is dismissed (normal or debug mode).
    @discardableResult
    func stopTracking() -> StoryVitalsSummary? {
        guard isTracking else { return nil }
        isTracking = false

        snapshotTimer?.invalidate()
        snapshotTimer = nil
        cancellables.removeAll()

#if canImport(SmartSpectraSwiftSDK)
        if sdkStarted {
            // Stop recording first, then processing — give the graph 200 ms to flush
            // its final packets before tearing down, which prevents the next
            // startProcessing() from racing with an in-flight graph shutdown.
            processor.stopRecording()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
                self.processor.stopProcessing()
            }
            print("[StoryVitalsTracker] ⏹  SDK stopped")
        }
        sdkStarted = false
#endif

        guard let storyId, let childId else { return nil }

        // Capture a final snapshot at the exact moment the story ends
        recordSnapshot()

        let summary = StoryVitalsSummary.compute(storyId: storyId, childId: childId, snapshots: snapshots)
        StoryVitalsStore.shared.save(summary)

        if let token = UserDefaults.standard.string(forKey: "accessToken") {
            Task { await postToBackend(summary: summary, token: token) }
        }

        self.storyId = nil
        self.childId = nil
        self.currentHeartRate = 0
        self.currentBreathingRate = 0
        self.statusHint = "Not started"
        self.eyeDrowsinessScore = 0
        self.smoothedEyeOpenness = 1.0
        self.blinkTimestamps = []
        self.eyesPreviouslyClosed = false

        return summary
    }

    // MARK: - Private

    private func recordSnapshot() {
        let snap = StoryVitalsSnapshot(
            timestamp: Date(),
            heartRate: currentHeartRate,
            breathingRate: currentBreathingRate,
            confidence: 1.0
        )
        snapshots.append(snap)
    }

#if canImport(SmartSpectraSwiftSDK)
    // MARK: - Eye drowsiness analysis

    /// Called each time SmartSpectra publishes new edgeMetrics (typed as `Metrics`).
    /// Uses face landmarks for eye openness and blinking array for blink detection.
    private func processEyeMetrics(edge: Metrics) {
        guard edge.hasFace else { return }
        let face = edge.face

        // ── Blink detection via face.blinking array ───────────────────────────
        // Each DetectionStatus has .detected: Bool and .time: Float
        if let latestBlink = face.blinking.last, latestBlink.detected {
            // Rising edge: only count if eyes were open before
            if !eyesPreviouslyClosed {
                blinkTimestamps.append(Date())
            }
            eyesPreviouslyClosed = true
        } else {
            eyesPreviouslyClosed = false
        }

        // Keep only blinks in the last 60 seconds
        let cutoff = Date().addingTimeInterval(-60)
        blinkTimestamps.removeAll { $0 < cutoff }
        let blinksPerMin = Double(blinkTimestamps.count)

        // ── Eye openness via face landmarks ───────────────────────────────────
        // face.landmarks is [Presage_Physiology_Landmarks], each has .value: [Presage_Physiology_Point2dFloat]
        // Point2dFloat has .x: Float and .y: Float
        var ear = 0.25  // fallback — assume open
        if let latestLandmarks = face.landmarks.last?.value, latestLandmarks.count > 386 {
            ear = computeEAR(landmarks: latestLandmarks)
        }

        // Exponential moving average to smooth blink frames
        let alpha = 0.25
        smoothedEyeOpenness = alpha * ear + (1 - alpha) * smoothedEyeOpenness

        // ── Eye openness drowsiness ───────────────────────────────────────────
        // EAR: ~0.30 = wide open, ~0.18 = closing, ~0.10 = closed
        let opennessDrowsiness = 1.0 - min(max((smoothedEyeOpenness - 0.10) / 0.20, 0), 1)

        // ── Blink rate drowsiness ─────────────────────────────────────────────
        // Normal: 12–20 blinks/min. Drowsy: < 6 (heavy lids) or > 25 (fighting sleep)
        let blinkDrowsiness: Double
        if blinksPerMin < 6 {
            blinkDrowsiness = min((6 - blinksPerMin) / 6, 1.0)
        } else if blinksPerMin > 25 {
            blinkDrowsiness = min((blinksPerMin - 25) / 15, 1.0)
        } else {
            blinkDrowsiness = 0
        }

        // Eye openness is the stronger signal (70%), blink rate supports it (30%)
        eyeDrowsinessScore = min(max(opennessDrowsiness * 0.70 + blinkDrowsiness * 0.30, 0), 1)
    }

    /// Computes Eye Aspect Ratio from a flat array of Point2dFloat landmarks.
    /// Uses MediaPipe 468-point mesh indices.
    private func computeEAR(landmarks: [Presage_Physiology_Point2dFloat]) -> Double {
        guard landmarks.count > 386 else { return 0.25 }

        // Left eye: upper lid 159, lower lid 145, inner corner 133, outer corner 33
        let leftEAR = eyeAspectRatio(
            upper: landmarks[159], lower: landmarks[145],
            inner: landmarks[133], outer: landmarks[33]
        )
        // Right eye: upper lid 386, lower lid 374, inner corner 362, outer corner 263
        let rightEAR = eyeAspectRatio(
            upper: landmarks[386], lower: landmarks[374],
            inner: landmarks[362], outer: landmarks[263]
        )
        return (leftEAR + rightEAR) / 2.0
    }

    private func eyeAspectRatio(
        upper: Presage_Physiology_Point2dFloat,
        lower: Presage_Physiology_Point2dFloat,
        inner: Presage_Physiology_Point2dFloat,
        outer: Presage_Physiology_Point2dFloat
    ) -> Double {
        let vertical   = sqrt(pow(Double(upper.x - lower.x), 2) + pow(Double(upper.y - lower.y), 2))
        let horizontal = sqrt(pow(Double(inner.x - outer.x), 2) + pow(Double(inner.y - outer.y), 2))
        guard horizontal > 0 else { return 0.25 }
        return vertical / horizontal
    }
#endif

    private func postToBackend(summary: StoryVitalsSummary, token: String) async {
        struct Body: Encodable {
            let childId: String
            let avgHeartRate: Double
            let avgBreathingRate: Double
            let minHeartRate: Double
            let maxHeartRate: Double
            let snapshots: [StoryVitalsSnapshot]
        }
        let body = Body(
            childId: summary.childId,
            avgHeartRate: summary.avgHeartRate,
            avgBreathingRate: summary.avgBreathingRate,
            minHeartRate: summary.minHeartRate,
            maxHeartRate: summary.maxHeartRate,
            snapshots: summary.snapshots
        )
        guard let url = URL(string: "\(APIService.baseURL)/api/stories/vitals/\(summary.storyId)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONEncoder().encode(body)
        _ = try? await URLSession.shared.data(for: req)
    }
}
