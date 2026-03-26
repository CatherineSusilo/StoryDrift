import Foundation
import Combine

class VitalsManager: ObservableObject {
    @Published var isMonitoring = false
    @Published var currentHeartRate: Double = 0
    @Published var currentBreathingRate: Double = 0
    @Published var signalQuality: Int = 0
    @Published var driftScore: Double = 0
    /// 0.0 = wide awake eyes, 1.0 = fully drowsy/closed eyes. Fed from SmartSpectra edgeMetrics.
    @Published var eyeDrowsinessScore: Double = 0

    private var cancellables = Set<AnyCancellable>()
    private var monitoringTask: Task<Void, Never>?
    private var childId: String?
    private var startTime: Date?

    let metricsPublisher = PassthroughSubject<VitalsMetrics, Never>()

    struct VitalsMetrics {
        let heartRate: Double
        let breathingRate: Double
        let signalQuality: Int
        let driftScore: Double
        let timestamp: Date
    }

    // MARK: - Public API for feeding vitals data from any SDK
    func updateVitals(heartRate: Double, breathingRate: Double, signalQuality: Int, eyeDrowsiness: Double = 0) {
        DispatchQueue.main.async {
            self.currentHeartRate = heartRate
            self.currentBreathingRate = breathingRate
            self.signalQuality = signalQuality
            self.eyeDrowsinessScore = eyeDrowsiness
            self.calculateDriftScore()

            let metrics = VitalsMetrics(
                heartRate: heartRate,
                breathingRate: breathingRate,
                signalQuality: signalQuality,
                driftScore: self.driftScore,
                timestamp: Date()
            )
            self.metricsPublisher.send(metrics)
        }
    }

    func startMonitoring(childId: String) {
        self.childId = childId
        self.startTime = Date()
        self.isMonitoring = true

        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)

                guard let self = self,
                      let childId = self.childId,
                      self.isMonitoring else { break }

                await self.postVitals(childId: childId)
            }
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
        childId = nil
        startTime = nil
    }

    private func calculateDriftScore() {
        guard let startTime = startTime else {
            driftScore = 0
            return
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let timeProgress = min(elapsed / 1200, 1.0)

        // Time-based baseline: up to 100 points over 20 min (normalised below)
        var score = timeProgress * 55

        // Heart rate: lower HR = more relaxed/sleepy — up to 20 pts
        if currentHeartRate > 0 {
            let hrFactor = max(0, (80 - currentHeartRate) / 30)
            score += hrFactor * 20
        }

        // Breathing rate: slower breathing = sleepier — up to 15 pts
        if currentBreathingRate > 0 {
            let brFactor = max(0, (16 - currentBreathingRate) / 8)
            score += brFactor * 15
        }

        // Eye drowsiness from SmartSpectra edgeMetrics:
        // slow blink rate + reduced eye openness → score 0–1 → up to 30 pts
        // This is the strongest single signal of imminent sleep onset.
        score += eyeDrowsinessScore * 30

        driftScore = min(max(score, 0), 100)
    }

    private func postVitals(childId: String) async {
        guard currentHeartRate > 0, currentBreathingRate > 0 else { return }

        let vitals = Vitals(
            childId: childId,
            timestamp: Date(),
            heartRate: currentHeartRate,
            breathingRate: currentBreathingRate,
            signalQuality: signalQuality
        )

        guard let token = UserDefaults.standard.string(forKey: "accessToken") else { return }

        do {
            try await APIService.shared.postVitals(vitals: vitals, token: token)
        } catch {
            print("Error posting vitals: \(error)")
        }
    }

    func getDriftPercentage() -> Int {
        return Int(driftScore)
    }

    func getDriftStatus() -> String {
        switch driftScore {
        case 0..<25:  return "Wide Awake"
        case 25..<50: return "Relaxing"
        case 50..<75: return "Drowsy"
        case 75..<90: return "Nearly Asleep"
        default:      return "Asleep"
        }
    }
}
