import Foundation

/// Measures tempo from a buffer of samples that contains one stroke, starting with a still pre-roll.
///
/// The AirPod sits in the butt end of the grip, so a putting stroke is almost a pure rotation
/// about one axis (a pendulum). We don't know how the AirPod is oriented, so we find that axis from
/// the data, project the gyro onto it, and read the stroke phases off the resulting 1-D signal:
///
/// - start:  angular velocity first rises above `onsetThreshold`
/// - top:    angular velocity crosses zero (putter changes direction)
/// - impact: integrated angle returns to where it was at address
public struct StrokeAnalyzer: Sendable {
    public struct Config: Sendable {
        /// Leading window assumed still, used to estimate gyro bias.
        public var biasWindow: TimeInterval = 0.2
        /// Speed (rad/s) that is definitely deliberate motion.
        public var triggerThreshold: Double = 0.15
        /// Speed (rad/s) treated as the moment motion began.
        public var onsetThreshold: Double = 0.05
        /// Anything smaller than this is a waggle, not a stroke.
        public var minBackswingAngle: Double = 2
        public var backswingRange: ClosedRange<TimeInterval> = 0.2...2.0
        public var downswingRange: ClosedRange<TimeInterval> = 0.08...1.2

        public init() {}
    }

    public var config: Config

    public init(config: Config = Config()) {
        self.config = config
    }

    public func analyze(_ samples: [MotionSample]) -> PuttStroke? {
        guard samples.count >= 5, let t0 = samples.first?.timestamp else { return nil }
        let times = samples.map(\.timestamp)

        let biasSamples = samples.prefix { $0.timestamp - t0 <= config.biasWindow }
        let bias = biasSamples.reduce(Vector3.zero) { $0 + $1.rotationRate } * (1 / Double(biasSamples.count))
        let omega = samples.map { $0.rotationRate - bias }

        guard let peak = omega.max(by: { $0.length < $1.length }), peak.length > config.triggerThreshold else {
            return nil
        }
        let axis = peak.normalized
        var p = omega.map { $0.dot(axis) }

        // Orient so the backswing is positive.
        guard let trigger = p.firstIndex(where: { abs($0) > config.triggerThreshold }) else { return nil }
        if p[trigger] < 0 { p = p.map { -$0 } }

        var onset = trigger
        while onset > 0 && p[onset - 1] > config.onsetThreshold { onset -= 1 }
        let startTime = onset > 0
            ? crossing(times, p, onset - 1, level: config.onsetThreshold)
            : times[0]

        guard let topIndex = (trigger + 1..<p.count).first(where: { p[$0] <= 0 }) else { return nil }
        let topTime = crossing(times, p, topIndex - 1, level: 0)

        // Integrate angular velocity into angle (trapezoid rule).
        var theta = [Double](repeating: 0, count: p.count)
        for i in 1..<p.count {
            theta[i] = theta[i - 1] + 0.5 * (p[i] + p[i - 1]) * (times[i] - times[i - 1])
        }
        let addressAngle = onset > 0 ? interpolate(times, theta, onset - 1, at: startTime) : theta[0]
        let relative = theta.map { $0 - addressAngle }

        guard let impactIndex = (topIndex..<p.count).first(where: { relative[$0] <= 0 }) else { return nil }
        let impactTime = crossing(times, relative, impactIndex - 1, level: 0)
        let impactSpeed = abs(interpolate(times, p, impactIndex - 1, at: impactTime))
        let backswingAngle = relative[onset..<impactIndex].max() ?? 0

        let stroke = PuttStroke(
            startTime: startTime,
            backswingDuration: topTime - startTime,
            downswingDuration: impactTime - topTime,
            backswingAngle: backswingAngle * 180 / .pi,
            impactAngularSpeed: impactSpeed * 180 / .pi
        )
        guard stroke.backswingAngle >= config.minBackswingAngle,
              config.backswingRange.contains(stroke.backswingDuration),
              config.downswingRange.contains(stroke.downswingDuration)
        else { return nil }
        return stroke
    }

    /// Time at which `values` crosses `level` between index `i` and `i + 1`, linearly interpolated.
    private func crossing(_ times: [Double], _ values: [Double], _ i: Int, level: Double) -> Double {
        let dv = values[i + 1] - values[i]
        guard dv != 0 else { return times[i + 1] }
        let f = min(max((level - values[i]) / dv, 0), 1)
        return times[i] + f * (times[i + 1] - times[i])
    }

    /// Value of `values` at time `t` lying between index `i` and `i + 1`.
    private func interpolate(_ times: [Double], _ values: [Double], _ i: Int, at t: Double) -> Double {
        let dt = times[i + 1] - times[i]
        guard dt > 0 else { return values[i] }
        return values[i] + (t - times[i]) / dt * (values[i + 1] - values[i])
    }
}
