import CoreMotion
import Observation
import PuttCore

/// Streams AirPods motion into a `StrokeDetector` and reports detected putts.
@MainActor
@Observable
final class HeadphoneMotionService: NSObject {
    private(set) var isConnected = false
    private(set) var isStreaming = false
    private(set) var phase: StrokeDetector.Phase = .waitingForAddress
    private(set) var errorMessage: String?

    @ObservationIgnored var onStroke: ((DetectedStroke) -> Void)?
    @ObservationIgnored private let manager = CMHeadphoneMotionManager()
    @ObservationIgnored private var detector = StrokeDetector()

    override init() {
        super.init()
        manager.delegate = self
    }

    func start() {
        guard manager.isDeviceMotionAvailable else {
            errorMessage = "Headphone motion isn't available on this device."
            return
        }
        if CMHeadphoneMotionManager.authorizationStatus() == .denied {
            errorMessage = "Motion access is off. Enable it in Settings › Privacy & Security › Motion & Fitness."
            return
        }
        errorMessage = nil
        detector.reset()
        phase = detector.phase
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            let sample = motion.map(MotionSample.init)
            MainActor.assumeIsolated {
                self?.handle(sample, error: error)
            }
        }
        isStreaming = true
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        isStreaming = false
        detector.reset()
        phase = detector.phase
    }

    private func handle(_ sample: MotionSample?, error: Error?) {
        if let error {
            errorMessage = error.localizedDescription
            return
        }
        guard let sample else { return }
        let detected = detector.process(sample)
        if phase != detector.phase { phase = detector.phase }
        if let detected { onStroke?(detected) }
    }
}

extension HeadphoneMotionService: CMHeadphoneMotionManagerDelegate {
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in self.isConnected = true }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in self.isConnected = false }
    }
}

extension MotionSample {
    init(_ motion: CMDeviceMotion) {
        self.init(
            timestamp: motion.timestamp,
            rotationRate: Vector3(x: motion.rotationRate.x, y: motion.rotationRate.y, z: motion.rotationRate.z),
            userAcceleration: Vector3(x: motion.userAcceleration.x, y: motion.userAcceleration.y, z: motion.userAcceleration.z)
        )
    }
}
