import Foundation
import Testing
@testable import PuttCore

/// Deterministic RNG so noisy tests are repeatable.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func gaussian(sd: Double) -> Double {
        let u1 = Double.random(in: .ulpOfOne..<1, using: &self)
        let u2 = Double.random(in: 0..<1, using: &self)
        return sd * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

/// Pendulum-like putt: smooth takeaway, putter accelerates through impact, then decelerates.
func syntheticPutt(
    backswing tb: Double,
    downswing td: Double,
    followThrough tf: Double = 0.4,
    amplitudeDegrees: Double = 15,
    axis: Vector3 = Vector3(x: 0.3, y: -0.8, z: 0.5),
    sampleRate: Double = 25,
    leadIn: Double = 1.0,
    tail: Double = 1.0,
    noise: Double = 0.01,
    bias: Vector3 = Vector3(x: 0.01, y: -0.005, z: 0.008),
    seed: UInt64 = 42
) -> [MotionSample] {
    var rng = SplitMix64(state: seed)
    let a = amplitudeDegrees * .pi / 180
    let unit = axis.normalized
    let t0 = 1000.013 // arbitrary, so samples don't line up with stroke events
    let duration = leadIn + tb + td + tf + tail

    func omega(_ t: Double) -> Double {
        switch t {
        case ..<0: 0
        case ..<tb: a * .pi / (2 * tb) * sin(.pi * t / tb)
        case ..<(tb + td): -a * .pi / (2 * td) * sin(.pi * (t - tb) / (2 * td))
        case ..<(tb + td + tf): -a * .pi / (2 * td) * cos(.pi * (t - tb - td) / (2 * tf))
        default: 0
        }
    }

    return stride(from: 0, to: duration, by: 1 / sampleRate).map { t in
        let w = unit * omega(t - leadIn) + bias
        let n = Vector3(x: rng.gaussian(sd: noise), y: rng.gaussian(sd: noise), z: rng.gaussian(sd: noise))
        return MotionSample(timestamp: t0 + t, rotationRate: w + n)
    }
}

@Suite struct StrokeAnalyzerTests {
    let analyzer = StrokeAnalyzer()

    @Test func measuresTourTempo() throws {
        let stroke = try #require(analyzer.analyze(syntheticPutt(backswing: 0.66, downswing: 0.33)))
        #expect(abs(stroke.backswingDuration - 0.66) < 0.04)
        #expect(abs(stroke.downswingDuration - 0.33) < 0.03)
        #expect(abs(stroke.tempoRatio - 2.0) < 0.2)
        #expect(abs(stroke.backswingAngle - 15) < 1.5)
        #expect(abs(stroke.startTime - 1001.013) < 0.04)
    }

    @Test(arguments: [(0.6, 0.4), (0.9, 0.3), (0.5, 0.25), (1.0, 0.33)])
    func recoversRatio(tb: Double, td: Double) throws {
        let stroke = try #require(analyzer.analyze(syntheticPutt(backswing: tb, downswing: td, seed: UInt64(tb * 1000))))
        #expect(abs(stroke.tempoRatio - tb / td) / (tb / td) < 0.1)
    }

    @Test func worksRegardlessOfAxisAndDirection() throws {
        let stroke = try #require(analyzer.analyze(
            syntheticPutt(backswing: 0.66, downswing: 0.33, axis: Vector3(x: -1, y: 0.1, z: -0.2))
        ))
        #expect(abs(stroke.tempoRatio - 2.0) < 0.2)
    }

    @Test func ignoresStillness() {
        #expect(analyzer.analyze(syntheticPutt(backswing: 0.66, downswing: 0.33, amplitudeDegrees: 0)) == nil)
    }

    @Test func rejectsWaggle() {
        #expect(analyzer.analyze(syntheticPutt(backswing: 0.15, downswing: 0.1, amplitudeDegrees: 1.5)) == nil)
    }
}

@Suite struct StrokeDetectorTests {
    @Test func detectsEachPuttInAStream() {
        let first = syntheticPutt(backswing: 0.66, downswing: 0.33, seed: 1)
        let offset = (first.last?.timestamp ?? 0) - 1000
        let second = syntheticPutt(backswing: 0.8, downswing: 0.4, seed: 2).map {
            MotionSample(timestamp: $0.timestamp + offset, rotationRate: $0.rotationRate)
        }

        var detector = StrokeDetector()
        var strokes: [PuttStroke] = []
        var sawReady = false
        for sample in first + second {
            if let detected = detector.process(sample) { strokes.append(detected.stroke) }
            if detector.phase == .ready { sawReady = true }
        }

        #expect(sawReady)
        #expect(strokes.count == 2)
        #expect(strokes.allSatisfy { abs($0.tempoRatio - 2.0) < 0.2 })
    }

    @Test func requiresAddressBeforeRecording() {
        // No still lead-in: the putter is already moving when the stream starts.
        var detector = StrokeDetector()
        let samples = syntheticPutt(backswing: 0.66, downswing: 0.33, leadIn: 0, tail: 0.2)
        #expect(samples.compactMap { detector.process($0) }.isEmpty)
    }
}

@Suite struct TempoStatsTests {
    func stroke(_ back: Double, _ down: Double) -> PuttStroke {
        PuttStroke(startTime: 0, backswingDuration: back, downswingDuration: down, backswingAngle: 10, impactAngularSpeed: 50)
    }

    @Test func summarisesSpread() throws {
        let stats = try #require(TempoStats([stroke(0.6, 0.3), stroke(0.8, 0.4), stroke(0.66, 0.3)]))
        #expect(stats.count == 3)
        #expect(abs(stats.tempoRatio.mean - (2 + 2 + 2.2) / 3) < 1e-9)
        #expect(abs(stats.tempoRatio.standardDeviation - 0.11547) < 1e-4)
    }

    @Test func emptyIsNil() {
        #expect(TempoStats([]) == nil)
    }
}
