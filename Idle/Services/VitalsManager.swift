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

    /// Persisted setting — user can disable camera in Settings.
    /// When false the backend uses synthetic biometrics derived from
    /// session time + child profile so stories still adapt naturally.
    @Published var isCameraEnabled: Bool {
        didSet { UserDefaults.standard.set(isCameraEnabled, forKey: "cameraEnabled") }
    }

    // Convenience aliases used by session views
    var heartRate: Double    { currentHeartRate }
    var breathingRate: Double { currentBreathingRate }

    private var cancellables = Set<AnyCancellable>()
    private var monitoringTask: Task<Void, Never>?
    private var childId: String?
    private var startTime: Date?
    
    // Synthetic drift score state (when camera is disabled)
    private var syntheticTimer: Timer?
    private var targetDuration: TimeInterval = 900 // default 15 min
    private var useSyntheticDrift = false

    let metricsPublisher = PassthroughSubject<VitalsMetrics, Never>()

    init() {
        self.isCameraEnabled = UserDefaults.standard.object(forKey: "cameraEnabled") as? Bool ?? true
    }

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

    func startMonitoring(childId: String, useSynthetic: Bool = false, targetDuration: TimeInterval = 900) {
        self.childId = childId
        self.startTime = Date()
        self.isMonitoring = true
        self.useSyntheticDrift = useSynthetic
        self.targetDuration = targetDuration
        
        if useSynthetic {
            // Start synthetic drift timer that updates every second
            syntheticTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.updateSyntheticDrift()
            }
        } else {
            // Normal camera-based monitoring
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
    }
    
    private func updateSyntheticDrift() {
        guard let startTime = startTime else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let progress = min(elapsed / targetDuration, 1.0)
        
        // Steady linear increase from 0 to 100 over the target duration
        // Add slight randomness for natural variation (±2%)
        let randomVariation = Double.random(in: -2...2)
        let baseScore = progress * 100
        let newScore = min(max(baseScore + randomVariation, 0), 100)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.driftScore = newScore
            
            // Set synthetic vitals that look realistic
            self.currentHeartRate = 80 - (progress * 17) // 80 → 63 BPM
            self.currentBreathingRate = 17 - (progress * 6) // 17 → 11 breaths/min
            self.signalQuality = 0 // No camera signal
            self.eyeDrowsinessScore = progress
            
            let metrics = VitalsMetrics(
                heartRate: self.currentHeartRate,
                breathingRate: self.currentBreathingRate,
                signalQuality: self.signalQuality,
                driftScore: self.driftScore,
                timestamp: Date()
            )
            self.metricsPublisher.send(metrics)
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
        syntheticTimer?.invalidate()
        syntheticTimer = nil
        childId = nil
        startTime = nil
        useSyntheticDrift = false
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
