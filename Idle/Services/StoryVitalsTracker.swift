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
/// Persists StoryVitalsSummary objects locally using UserDefaults (lightweight, no backend schema change required).
/// Keyed by childId so each child has their own list.
class StoryVitalsStore {
    static let shared = StoryVitalsStore()
    private let key = "storyVitalsSummaries_v1"

    func save(_ summary: StoryVitalsSummary) {
        var all = loadAll()
        // Replace if same storyId already exists
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
/// Observable service that wraps SmartSpectra headless vitals processing during a story session.
/// Uses the existing VitalsManager as the downstream sink for DriftMeter integration.
/// All SmartSpectra SDK calls are wrapped in compiler guards so the project compiles
/// even before the SPM package has been added in Xcode.
class StoryVitalsTracker: ObservableObject {
    static let shared = StoryVitalsTracker()

    // Forwarded from SmartSpectra / VitalsManager
    @Published var currentHeartRate: Double = 0
    @Published var currentBreathingRate: Double = 0
    @Published var isTracking: Bool = false
    @Published var statusHint: String = "Not started"

    private var snapshots: [StoryVitalsSnapshot] = []
    private var snapshotTimer: Timer?
    private var storyId: String?
    private var childId: String?

    private var cancellables = Set<AnyCancellable>()

#if canImport(SmartSpectraSwiftSDK)
    private let sdk = SmartSpectraSwiftSDK.shared
    private let processor = SmartSpectraVitalsProcessor.shared
#endif

    // MARK: - Lifecycle

    /// Call when the story screen appears. Starts the SmartSpectra headless processor.
    func startTracking(storyId: String, childId: String, vitalsManager: VitalsManager) {
        guard !isTracking else { return }

        self.storyId = storyId
        self.childId = childId
        self.snapshots = []
        self.isTracking = true

#if canImport(SmartSpectraSwiftSDK)
        // Configure SDK — skip if API key not yet set
        guard let apiKey = Secrets.smartSpectraAPIKey else {
            statusHint = "SmartSpectra API key not configured"
            print("[StoryVitalsTracker] ⚠️  Set SMARTSPECTRA_API_KEY in Config.xcconfig to enable vitals tracking.")
            return
        }
        sdk.setApiKey(apiKey)
        sdk.setSmartSpectraMode(.continuous)
        sdk.setCameraPosition(.front)

        // Start headless processing
        processor.startProcessing()
        processor.startRecording()

        // Observe vitals from the SDK and forward to VitalsManager
        sdk.$metricsBuffer
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak vitalsManager] buffer in
                guard let self, let buffer, let vitalsManager else { return }

                // Latest pulse rate
                let hr = buffer.pulse.rate.last.map { Double($0.value) } ?? 0
                let hrConf = buffer.pulse.rate.last.map { $0.confidence } ?? 0
                // Latest breathing rate
                let br = buffer.breathing.rate.last.map { Double($0.value) } ?? 0

                self.currentHeartRate = hr
                self.currentBreathingRate = br
                self.statusHint = self.processor.statusHint

                // Forward into existing VitalsManager for DriftMeter
                vitalsManager.updateVitals(
                    heartRate: hr,
                    breathingRate: br,
                    signalQuality: Int(hrConf * 100)
                )
            }
            .store(in: &cancellables)
#else
        // Simulator / SDK not yet linked — emit a log so developer knows
        statusHint = "SmartSpectra SDK not linked (simulator mode)"
        print("[StoryVitalsTracker] SmartSpectraSwiftSDK not available — running without vitals.")
#endif

        // Snapshot every 10 seconds
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.recordSnapshot()
        }
    }

    /// Call when the story ends (completed or dismissed). Stops SmartSpectra and persists summary.
    @discardableResult
    func stopTracking() -> StoryVitalsSummary? {
        guard isTracking else { return nil }
        isTracking = false
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        cancellables.removeAll()

#if canImport(SmartSpectraSwiftSDK)
        processor.stopRecording()
        processor.stopProcessing()
#endif

        guard let storyId, let childId else { return nil }

        // Record a final snapshot before summarising
        recordSnapshot()

        let summary = StoryVitalsSummary.compute(storyId: storyId, childId: childId, snapshots: snapshots)
        StoryVitalsStore.shared.save(summary)

        // Fire-and-forget: post to backend if token available
        if let token = UserDefaults.standard.string(forKey: "accessToken") {
            Task { await postToBackend(summary: summary, token: token) }
        }

        self.storyId = nil
        self.childId = nil
        self.currentHeartRate = 0
        self.currentBreathingRate = 0
        self.statusHint = "Not started"
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
