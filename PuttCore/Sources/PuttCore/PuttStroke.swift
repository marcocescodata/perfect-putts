import Foundation

/// Tempo metrics for a single putting stroke.
public struct PuttStroke: Sendable, Codable, Equatable {
    /// Sensor timestamp at which the backswing began.
    public var startTime: TimeInterval
    /// Takeaway to top of backswing, seconds.
    public var backswingDuration: TimeInterval
    /// Top of backswing to impact, seconds.
    public var downswingDuration: TimeInterval
    /// How far the putter rotated on the way back, degrees. A proxy for stroke length.
    public var backswingAngle: Double
    /// Putter rotation speed at impact, degrees/second. A proxy for pace.
    public var impactAngularSpeed: Double

    public init(
        startTime: TimeInterval,
        backswingDuration: TimeInterval,
        downswingDuration: TimeInterval,
        backswingAngle: Double,
        impactAngularSpeed: Double
    ) {
        self.startTime = startTime
        self.backswingDuration = backswingDuration
        self.downswingDuration = downswingDuration
        self.backswingAngle = backswingAngle
        self.impactAngularSpeed = impactAngularSpeed
    }

    /// Backswing time divided by downswing time. Tour players tend to sit close to 2.0.
    public var tempoRatio: Double { backswingDuration / downswingDuration }

    /// Takeaway to impact, seconds.
    public var totalDuration: TimeInterval { backswingDuration + downswingDuration }
}

/// A stroke plus the raw samples it was measured from, kept so detection can be re-run later.
public struct DetectedStroke: Sendable, Equatable {
    public var stroke: PuttStroke
    public var samples: [MotionSample]
}
