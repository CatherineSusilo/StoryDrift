import Foundation
import SmartSpectraSwiftSDK
import Combine

class SmartSpectraManager: ObservableObject {
    @Published var isMonitoring = false
    @Published var currentHeartRate: Double = 0
    @Published var currentBreathingRate: Double = 0
    @Published var signalQuality: Int = 0
    @Published var driftScore: Double = 0
    
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
    
    init() {
        setupObservers()
    }
    
    private func setupObservers() {
        // Observe SmartSpectra SDK metrics
        NotificationCenter.default.publisher(for: .init("SmartSpectraMetricsUpdated"))
            .sink { [weak self] notification in
                guard let self = self else { return }
                
                if let userInfo = notification.userInfo,
                   let hr = userInfo["heartRate"] as? Double,
                   let br = userInfo["breathingRate"] as? Double,
                   let quality = userInfo["signalQuality"] as? Int {
                    
                    DispatchQueue.main.async {
                        self.currentHeartRate = hr
                        self.currentBreathingRate = br
                        self.signalQuality = quality
                        self.calculateDriftScore()
                        
                        let metrics = VitalsMetrics(
                            heartRate: hr,
                            breathingRate: br,
                            signalQuality: quality,
                            driftScore: self.driftScore,
                            timestamp: Date()
                        )
                        
                        self.metricsPublisher.send(metrics)
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func startMonitoring(childId: String) {
        self.childId = childId
        self.startTime = Date()
        self.isMonitoring = true
        
        // Start posting vitals to backend every 5 seconds
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                
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
        let timeProgress = min(elapsed / 1200, 1.0) // 20 minutes max
        
        // Baseline drift from time alone
        var score = timeProgress * 100
        
        // Adjust based on vitals if available
        if currentHeartRate > 0 {
            // Lower heart rate increases drift
            // Assuming resting HR ~60-80, sleep HR ~50-60
            let hrFactor = max(0, (80 - currentHeartRate) / 30)
            score += hrFactor * 20
        }
        
        if currentBreathingRate > 0 {
            // Lower breathing rate increases drift
            // Assuming normal ~12-20, sleep ~8-12
            let brFactor = max(0, (16 - currentBreathingRate) / 8)
            score += brFactor * 15
        }
        
        // Clamp between 0-100
        driftScore = min(max(score, 0), 100)
    }
    
    private func postVitals(childId: String) async {
        guard currentHeartRate > 0,
              currentBreathingRate > 0 else {
            return
        }
        
        let vitals = Vitals(
            childId: childId,
            timestamp: Date(),
            heartRate: currentHeartRate,
            breathingRate: currentBreathingRate,
            signalQuality: signalQuality
        )
        
        // Get auth token
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            print("No auth token available")
            return
        }
        
        do {
            try await APIService.shared.postVitals(vitals: vitals, token: token)
            print("Vitals posted: HR=\(currentHeartRate), BR=\(currentBreathingRate), Drift=\(driftScore)%")
        } catch {
            print("Error posting vitals: \(error)")
        }
    }
    
    func getDriftPercentage() -> Int {
        return Int(driftScore)
    }
    
    func getDriftStatus() -> String {
        switch driftScore {
        case 0..<25:
            return "Wide Awake"
        case 25..<50:
            return "Relaxing"
        case 50..<75:
            return "Drowsy"
        case 75..<90:
            return "Nearly Asleep"
        default:
            return "Asleep"
        }
    }
}
