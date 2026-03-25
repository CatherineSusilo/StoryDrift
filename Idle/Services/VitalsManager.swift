import Foundation
import Combine

class VitalsManager: ObservableObject {
    @Published var isMonitoring = false
    @Published var currentHeartRate: Double = 0
    @Published var currentBreathingRate: Double = 0
    @Published var signalQuality: Int = 0
    @Published var driftScore: Double = 0

    /// Persisted setting — user can disable camera in Settings.
    /// When false the backend uses synthetic biometrics derived from
    /// session time + child profile so stories still adapt naturally.
    @Published var isCameraEnabled: Bool {
        didSet { UserDefaults.standard.set(isCameraEnabled, forKey: "cameraEnabled") }
    }

    init() {
        self.isCameraEnabled = UserDefaults.standard.object(forKey: "cameraEnabled") as? Bool ?? true
    }

    private var cancellables = Set<AnyCancellable>()
    private var monitoringTask: Task<Void, Never>?
    private var childId: String?
    private var startTime: Date?

    // Convenience aliases used by session views
    var heartRate: Double    { currentHeartRate }
    var breathingRate: Double { currentBreathingRate }

    let metricsPublisher = PassthroughSubject<VitalsMetrics, Never>()

    struct VitalsMetrics {
        let heartRate: Double
        let breathingRate: Double
        let signalQuality: Int
        let driftScore: Double
        let timestamp: Date
    }

    // MARK: - Public API for feeding vitals data from any SDK
    func updateVitals(heartRate: Double, breathingRate: Double, signalQuality: Int) {
        DispatchQueue.main.async {
            self.currentHeartRate = heartRate
            self.currentBreathingRate = breathingRate
            self.signalQuality = signalQuality
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

        var score = timeProgress * 100

        if currentHeartRate > 0 {
            let hrFactor = max(0, (80 - currentHeartRate) / 30)
            score += hrFactor * 20
        }

        if currentBreathingRate > 0 {
            let brFactor = max(0, (16 - currentBreathingRate) / 8)
            score += brFactor * 15
        }

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
