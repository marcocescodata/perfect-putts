import Foundation

/// Consistency summary for a set of strokes. Lower spread = more repeatable stroke.
public struct TempoStats: Sendable, Equatable {
    public struct Summary: Sendable, Equatable {
        public var mean: Double
        /// Sample standard deviation (0 for a single value).
        public var standardDeviation: Double
        /// Standard deviation as a fraction of the mean — comparable across metrics.
        public var coefficientOfVariation: Double { mean == 0 ? 0 : standardDeviation / mean }

        init(_ values: [Double]) {
            let n = Double(values.count)
            mean = values.reduce(0, +) / n
            let m = mean
            standardDeviation = values.count > 1
                ? (values.map { ($0 - m) * ($0 - m) }.reduce(0, +) / (n - 1)).squareRoot()
                : 0
        }
    }

    public var count: Int
    public var tempoRatio: Summary
    public var totalDuration: Summary
    public var backswingDuration: Summary
    public var downswingDuration: Summary
    public var backswingAngle: Summary

    public init?(_ strokes: [PuttStroke]) {
        guard !strokes.isEmpty else { return nil }
        count = strokes.count
        tempoRatio = Summary(strokes.map(\.tempoRatio))
        totalDuration = Summary(strokes.map(\.totalDuration))
        backswingDuration = Summary(strokes.map(\.backswingDuration))
        downswingDuration = Summary(strokes.map(\.downswingDuration))
        backswingAngle = Summary(strokes.map(\.backswingAngle))
    }
}
