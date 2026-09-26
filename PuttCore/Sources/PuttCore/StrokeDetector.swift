import Foundation

/// Streams live motion samples and emits a `DetectedStroke` each time a putt is completed.
///
/// Flow: hold still over the ball (address) → `ready` → motion starts the recording → once the
/// putter settles again the buffer is handed to `StrokeAnalyzer`.
public struct StrokeDetector: Sendable {
    public enum Phase: Sendable, Equatable {
        case waitingForAddress
        case ready
        case inStroke
    }

    public struct Config: Sendable {
        /// Below this rotation speed (rad/s) the putter counts as still.
        public var stillThreshold: Double = 0.1
        /// How long to hold still at address before a stroke will be recorded.
        public var addressDuration: TimeInterval = 0.5
        /// Rotation speed (rad/s) that starts a recording.
        public var triggerThreshold: Double = 0.2
        /// How long the putter must be still after the stroke to end the recording.
        public var settleDuration: TimeInterval = 0.4
        public var maxStrokeDuration: TimeInterval = 4
        /// Samples kept from before the trigger, so the analyzer sees address and takeaway.
        public var preRoll: TimeInterval = 0.5

        public init() {}
    }

    public private(set) var phase: Phase = .waitingForAddress
    public var config: Config
    public var analyzer: StrokeAnalyzer

    private var history: [MotionSample] = []
    private var recording: [MotionSample] = []
    private var stillSince: TimeInterval?
    private var triggerTime: TimeInterval = 0

    public init(config: Config = Config(), analyzer: StrokeAnalyzer = StrokeAnalyzer()) {
        self.config = config
        self.analyzer = analyzer
    }

    public mutating func process(_ sample: MotionSample) -> DetectedStroke? {
        let speed = sample.rotationRate.length
        if speed < config.stillThreshold {
            if stillSince == nil { stillSince = sample.timestamp }
        } else {
            stillSince = nil
        }
        let stillFor = stillSince.map { sample.timestamp - $0 } ?? 0

        switch phase {
        case .waitingForAddress, .ready:
            history.append(sample)
            history.removeAll { sample.timestamp - $0.timestamp > config.preRoll }
            if phase == .waitingForAddress, stillFor >= config.addressDuration {
                phase = .ready
            } else if phase == .ready, speed > config.triggerThreshold {
                phase = .inStroke
                recording = history
                triggerTime = sample.timestamp
            }
            return nil

        case .inStroke:
            recording.append(sample)
            let settled = stillFor >= config.settleDuration
            let timedOut = sample.timestamp - triggerTime > config.maxStrokeDuration
            guard settled || timedOut else { return nil }

            let samples = recording
            recording = []
            history = []
            stillSince = nil
            phase = .waitingForAddress
            return analyzer.analyze(samples).map { DetectedStroke(stroke: $0, samples: samples) }
        }
    }

    public mutating func reset() {
        self = StrokeDetector(config: config, analyzer: analyzer)
    }
}
