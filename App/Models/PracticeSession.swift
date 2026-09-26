import Foundation
import PuttCore
import SwiftData

@Model
final class PracticeSession {
    var startedAt: Date
    var endedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \StrokeRecord.session)
    var strokes: [StrokeRecord] = []

    init(startedAt: Date = .now) {
        self.startedAt = startedAt
    }

    var orderedStrokes: [StrokeRecord] { strokes.sorted { $0.recordedAt < $1.recordedAt } }

    var stats: TempoStats? { TempoStats(orderedStrokes.map(\.metrics)) }
}

@Model
final class StrokeRecord {
    var recordedAt: Date
    var backswingDuration: Double
    var downswingDuration: Double
    var backswingAngle: Double
    var impactAngularSpeed: Double
    /// JSON-encoded `[MotionSample]`, kept so strokes can be re-analysed as detection improves.
    @Attribute(.externalStorage) var rawSamples: Data?
    var session: PracticeSession?

    init(_ detected: DetectedStroke, recordedAt: Date = .now) {
        self.recordedAt = recordedAt
        backswingDuration = detected.stroke.backswingDuration
        downswingDuration = detected.stroke.downswingDuration
        backswingAngle = detected.stroke.backswingAngle
        impactAngularSpeed = detected.stroke.impactAngularSpeed
        rawSamples = try? JSONEncoder().encode(detected.samples)
    }

    var metrics: PuttStroke {
        PuttStroke(
            startTime: 0,
            backswingDuration: backswingDuration,
            downswingDuration: downswingDuration,
            backswingAngle: backswingAngle,
            impactAngularSpeed: impactAngularSpeed
        )
    }
}
