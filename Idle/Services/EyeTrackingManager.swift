import Foundation
import Combine
import ARKit
import Vision
import AVFoundation
import UIKit

enum EyeTrackingMode {
    case arKit
    case vision
    case unavailable
}

enum FaceLossPhase {
    /// Face visible (or never lost yet this session).
    case normal
    /// Face missing — retry every 15s for up to 2 minutes.
    case shortRetry
    /// 2 minutes elapsed without face — feature paused; probe for face every 2 minutes.
    case longRetry
}

/// Native eye-tracking drift detection.
///
/// - ARKit `ARFaceAnchor` blend shapes on Face-ID-capable devices (TrueDepth — works in
///   the dark and at angles via IR depth sensor).
/// - Vision `VNDetectFaceLandmarksRequest` fallback. Multi-orientation probing handles
///   children lying on their side; low-light boost + auto exposure handles dim rooms.
///
/// `driftScore` is on the existing 0–100 scale (backend image pipeline + `DriftMeterView`
/// depend on this range). PERCLOS over a 30-second rolling window:
///   PERCLOS < 0.08    → 0–25   (alert)
///   PERCLOS 0.08–0.15 → 25–60  (drowsy)
///   PERCLOS > 0.15    → 60–100 (very drowsy / asleep)
///
/// Face-loss policy: when the face disappears (no detection for ~3s), drift score is
/// FROZEN at its latest value — it never decays back to 0. Recovery sequence:
///   1. shortRetry (0–120s): re-init capture every 15s.
///   2. longRetry  (120s+):  capture paused; brief 10s probe every 120s until stop.
@MainActor
final class EyeTrackingManager: NSObject, ObservableObject {

    static let shared = EyeTrackingManager()

    // MARK: - Public state

    @Published private(set) var driftScore: Double = 0
    @Published private(set) var trackingMode: EyeTrackingMode = .unavailable
    @Published private(set) var isTracking: Bool = false
    @Published private(set) var isMonitoring: Bool = false
    @Published private(set) var faceVisible: Bool = false
    @Published private(set) var faceLossPhase: FaceLossPhase = .normal

    @Published var isCameraEnabled: Bool {
        didSet { UserDefaults.standard.set(isCameraEnabled, forKey: "cameraEnabled") }
    }

    // MARK: - Tuning

    private let rollingWindow: TimeInterval = 30
    private let earClosedThreshold: Double = 0.21
    /// Single-eye EAR for sideways pose where one eye is occluded.
    private let singleEyeClosedThreshold: Double = 0.19
    private let faceLossThreshold: TimeInterval = 3
    private let shortRetryInterval: TimeInterval = 15
    private let shortRetryWindow: TimeInterval = 120        // 2 min of 15s retries
    private let longRetryInterval: TimeInterval = 120       // 2 min cycle thereafter
    private let longRetryProbeDuration: TimeInterval = 10   // active probe per long cycle

    private let visionOrientations: [CGImagePropertyOrientation] =
        [.leftMirrored, .rightMirrored, .upMirrored, .downMirrored]

    // MARK: - Private state

    private var startTime: Date?
    private var targetDuration: TimeInterval = 900

    private var samples: [(t: TimeInterval, closed: Bool)] = []

    // ARKit
    private var arSession: ARSession?

    // Vision
    private var captureSession: AVCaptureSession?
    private var captureDevice: AVCaptureDevice?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoQueue = DispatchQueue(label: "EyeTrackingManager.video", qos: .userInitiated)
    private let visionRequest = VNDetectFaceLandmarksRequest()
    /// Last orientation that yielded a face — try first on next frame.
    private var lastGoodOrientation: CGImagePropertyOrientation = .leftMirrored

    // Synthetic
    private var syntheticTimer: Timer?
    private var driftTimer: Timer?

    // Face-loss state machine
    private var lastFaceTime: Date?
    private var faceLossStartTime: Date?
    private var watchdogTimer: Timer?
    private var retryTimer: Timer?
    private var longProbeTimer: Timer?

    private override init() {
        self.isCameraEnabled = UserDefaults.standard.object(forKey: "cameraEnabled") as? Bool ?? true
        super.init()
    }

    // MARK: - Mode resolution

    static func resolveMode(cameraEnabled: Bool) -> EyeTrackingMode {
        guard cameraEnabled else { return .unavailable }
        if ARFaceTrackingConfiguration.isSupported { return .arKit }
        if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil {
            return .vision
        }
        return .unavailable
    }

    // MARK: - Public API

    func startTracking(targetDuration: TimeInterval = 900) {
        guard !isTracking else { return }
        self.targetDuration = targetDuration
        self.startTime = Date()
        self.samples.removeAll(keepingCapacity: true)
        self.driftScore = 0
        self.isTracking = true
        self.isMonitoring = true
        self.faceVisible = false
        self.faceLossPhase = .normal
        self.lastFaceTime = nil
        self.faceLossStartTime = nil

        trackingMode = Self.resolveMode(cameraEnabled: isCameraEnabled)

        switch trackingMode {
        case .arKit:    startARKit()
        case .vision:   startVision()
        case .unavailable: startSynthetic()
        }

        driftTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recalculateDrift() }
        }

        // Watchdog only runs when we actually have a camera-based source.
        if trackingMode != .unavailable {
            watchdogTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.watchdogTick() }
            }
        }
    }

    func stopTracking() {
        guard isTracking else { return }
        isTracking = false
        isMonitoring = false
        faceVisible = false
        faceLossPhase = .normal

        teardownCameraSources()

        syntheticTimer?.invalidate();  syntheticTimer = nil
        driftTimer?.invalidate();      driftTimer = nil
        watchdogTimer?.invalidate();   watchdogTimer = nil
        retryTimer?.invalidate();      retryTimer = nil
        longProbeTimer?.invalidate();  longProbeTimer = nil

        startTime = nil
        samples.removeAll(keepingCapacity: false)
    }

    func resetScore() {
        samples.removeAll(keepingCapacity: true)
        driftScore = 0
    }

    // MARK: - Status helpers

    func getDriftPercentage() -> Int { Int(driftScore) }

    func getDriftStatus() -> String {
        switch driftScore {
        case 0..<25:  return "Wide Awake"
        case 25..<50: return "Relaxing"
        case 50..<75: return "Drowsy"
        case 75..<90: return "Nearly Asleep"
        default:      return "Asleep"
        }
    }

    // MARK: - Source lifecycle

    private func teardownCameraSources() {
        arSession?.pause()
        arSession = nil

        if let session = captureSession {
            videoQueue.async { session.stopRunning() }
        }
        captureSession = nil
        videoOutput = nil
        captureDevice = nil
    }

    private func restartCurrentSource() {
        switch trackingMode {
        case .arKit:
            arSession?.pause()
            arSession = nil
            startARKit()
        case .vision:
            if let session = captureSession {
                videoQueue.async { session.stopRunning() }
            }
            captureSession = nil
            videoOutput = nil
            captureDevice = nil
            startVision()
        case .unavailable:
            break
        }
    }

    // MARK: - ARKit path

    private func startARKit() {
        let session = ARSession()
        session.delegate = self
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        // TrueDepth + IR works in the dark and at angles — no extra tuning needed.
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        arSession = session
    }

    fileprivate func ingestARFace(_ anchor: ARFaceAnchor) {
        let leftBlink  = (anchor.blendShapes[.eyeBlinkLeft]  as? Float) ?? 0
        let rightBlink = (anchor.blendShapes[.eyeBlinkRight] as? Float) ?? 0
        let closure = Double((leftBlink + rightBlink) / 2.0)
        markFaceVisible()
        addSample(closed: closure > 0.7)
    }

    // MARK: - Vision path

    private func startVision() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            trackingMode = .unavailable
            startSynthetic()
            return
        }

        configureForLowLight(device: device)

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        guard session.canAddInput(input) else {
            trackingMode = .unavailable
            startSynthetic()
            return
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)

        guard session.canAddOutput(output) else {
            trackingMode = .unavailable
            startSynthetic()
            return
        }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            if #available(iOS 17.0, *) {
                connection.videoRotationAngle = 90
            }
            connection.isVideoMirrored = true
        }

        // Throttle to ~15 fps to save battery (still plenty for PERCLOS).
        if let fmt = device.activeFormat.videoSupportedFrameRateRanges.first,
           (try? device.lockForConfiguration()) != nil {
            let fps = min(15.0, fmt.maxFrameRate)
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(fps))
            device.unlockForConfiguration()
        }

        session.commitConfiguration()
        captureSession = session
        captureDevice = device
        videoOutput = output

        videoQueue.async { session.startRunning() }
    }

    private func configureForLowLight(device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }

        if device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = true
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
    }

    fileprivate func ingestVisionSampleBuffer(_ buffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }

        // Try last-good orientation first; on miss try others.
        let ordered: [CGImagePropertyOrientation] = {
            var arr = visionOrientations
            if let i = arr.firstIndex(of: lastGoodOrientation) {
                arr.remove(at: i); arr.insert(lastGoodOrientation, at: 0)
            }
            return arr
        }()

        for orientation in ordered {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
            do { try handler.perform([visionRequest]) } catch { continue }
            guard let face = visionRequest.results?.first else { continue }

            let leftEAR  = face.landmarks?.leftEye.map  { earFor(eye: $0) }
            let rightEAR = face.landmarks?.rightEye.map { earFor(eye: $0) }

            let closed: Bool
            switch (leftEAR, rightEAR) {
            case (let l?, let r?):
                closed = ((l + r) / 2.0) < earClosedThreshold
            case (let l?, nil):
                closed = l < singleEyeClosedThreshold      // sideways pose
            case (nil, let r?):
                closed = r < singleEyeClosedThreshold
            default:
                continue                                    // landmarks failed, try next orientation
            }

            Task { @MainActor in
                self.lastGoodOrientation = orientation
                self.markFaceVisible()
                self.addSample(closed: closed)
            }
            return
        }
        // Silent miss — watchdog will pick up if it persists.
    }

    /// 6-point Eye Aspect Ratio (Soukupová & Čech). Vision returns more than 6 landmarks;
    /// pick corners by x-extremes and top/bottom by y in each half.
    private func earFor(eye: VNFaceLandmarkRegion2D) -> Double {
        let pts = (0..<eye.pointCount).map { eye.normalizedPoints[$0] }
        guard pts.count >= 6 else { return 1.0 }
        let sortedX = pts.sorted { $0.x < $1.x }
        let p1 = sortedX.first!
        let p4 = sortedX.last!
        let mid = pts.filter { $0 != p1 && $0 != p4 }
        let leftHalf  = mid.filter { $0.x <= (p1.x + p4.x) / 2 }
        let rightHalf = mid.filter { $0.x >  (p1.x + p4.x) / 2 }
        guard let p2 = leftHalf.max(by: { $0.y < $1.y }),
              let p6 = leftHalf.min(by: { $0.y < $1.y }),
              let p3 = rightHalf.max(by: { $0.y < $1.y }),
              let p5 = rightHalf.min(by: { $0.y < $1.y }) else { return 1.0 }
        let v1 = distance(p2, p6)
        let v2 = distance(p3, p5)
        let h  = distance(p1, p4)
        guard h > 0 else { return 1.0 }
        return (v1 + v2) / (2.0 * h)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return Double(sqrt(dx * dx + dy * dy))
    }

    // MARK: - Synthetic path

    private func startSynthetic() {
        syntheticTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateSynthetic() }
        }
    }

    private func updateSynthetic() {
        guard let startTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        let progress = min(elapsed / targetDuration, 1.0)
        let jitter = Double.random(in: -2...2)
        // Cap synthetic drift at 90 — without eye tracking it otherwise hits
        // 100 before the story ends. Reserve 100 for real PERCLOS detection.
        driftScore = min(max(progress * 100 + jitter, 0), 90)
    }

    // MARK: - PERCLOS

    private func addSample(closed: Bool) {
        guard let startTime else { return }
        let t = Date().timeIntervalSince(startTime)
        samples.append((t, closed))
        let cutoff = t - rollingWindow
        if let firstKeep = samples.firstIndex(where: { $0.t >= cutoff }), firstKeep > 0 {
            samples.removeFirst(firstKeep)
        }
        recalculateDrift()
    }

    private func recalculateDrift() {
        guard trackingMode != .unavailable else { return }
        // Face missing → freeze score at its latest value (do NOT recompute from a
        // stale or empty buffer).
        guard !samples.isEmpty, faceVisible else { return }
        let closedCount = samples.lazy.filter { $0.closed }.count
        let perclos = Double(closedCount) / Double(samples.count)
        driftScore = mapPERCLOSToDrift(perclos)
    }

    /// PERCLOS → 0–100 drift score. Exposed `internal` for unit tests.
    nonisolated static func mapPERCLOSToDrift(_ perclos: Double) -> Double {
        let p = min(max(perclos, 0), 1)
        if p < 0.08 {
            return (p / 0.08) * 25.0
        } else if p < 0.15 {
            return 25.0 + ((p - 0.08) / 0.07) * 35.0
        } else {
            return min(60.0 + ((p - 0.15) / 0.35) * 40.0, 100.0)
        }
    }

    private func mapPERCLOSToDrift(_ perclos: Double) -> Double {
        Self.mapPERCLOSToDrift(perclos)
    }

    // MARK: - Face-loss state machine

    private func markFaceVisible() {
        lastFaceTime = Date()
        if !faceVisible { faceVisible = true }
        if faceLossPhase != .normal {
            faceLossPhase = .normal
            faceLossStartTime = nil
            retryTimer?.invalidate();     retryTimer = nil
            longProbeTimer?.invalidate(); longProbeTimer = nil
        }
    }

    private func watchdogTick() {
        guard isTracking, trackingMode != .unavailable else { return }
        let now = Date()
        let last = lastFaceTime ?? startTime ?? now
        let sinceFace = now.timeIntervalSince(last)

        guard sinceFace > faceLossThreshold else { return }

        if faceVisible { faceVisible = false }

        switch faceLossPhase {
        case .normal:
            enterShortRetry()
        case .shortRetry, .longRetry:
            break  // managed by their own timers
        }
    }

    private func enterShortRetry() {
        faceLossPhase = .shortRetry
        faceLossStartTime = Date()
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: shortRetryInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.shortRetryTick() }
        }
    }

    private func shortRetryTick() {
        guard isTracking, faceLossPhase == .shortRetry else { return }
        let elapsed = Date().timeIntervalSince(faceLossStartTime ?? Date())
        if elapsed >= shortRetryWindow {
            enterLongRetry()
        } else {
            restartCurrentSource()
        }
    }

    private func enterLongRetry() {
        faceLossPhase = .longRetry
        retryTimer?.invalidate(); retryTimer = nil
        teardownCameraSources()  // turn camera off — feature temporarily disabled

        retryTimer = Timer.scheduledTimer(withTimeInterval: longRetryInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.longRetryTick() }
        }
    }

    private func longRetryTick() {
        guard isTracking, faceLossPhase == .longRetry else { return }
        // Bring source back up for a short probe window.
        switch trackingMode {
        case .arKit:  startARKit()
        case .vision: startVision()
        case .unavailable: return
        }

        longProbeTimer?.invalidate()
        longProbeTimer = Timer.scheduledTimer(withTimeInterval: longRetryProbeDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.longRetryProbeEnded() }
        }
    }

    private func longRetryProbeEnded() {
        guard isTracking, faceLossPhase == .longRetry else { return }
        if faceVisible {
            // markFaceVisible already reset phase to .normal — nothing to do.
            return
        }
        teardownCameraSources()  // give up this probe; next cycle in longRetryInterval seconds
    }
}

// MARK: - ARSessionDelegate

extension EyeTrackingManager: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let faceAnchor = anchor as? ARFaceAnchor, faceAnchor.isTracked else { continue }
            Task { @MainActor in self.ingestARFace(faceAnchor) }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension EyeTrackingManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        let buffer = sampleBuffer
        Task { await self.ingestVisionSampleBuffer(buffer) }
    }
}
