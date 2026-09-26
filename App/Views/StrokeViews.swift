import PuttCore
import SwiftUI

struct StrokeSummary: View {
    let stroke: PuttStroke

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(stroke.tempoRatio, format: .number.precision(.fractionLength(2)))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                + Text(" : 1").font(.title2).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                Metric(label: "Back", value: ms(stroke.backswingDuration))
                Metric(label: "Through", value: ms(stroke.downswingDuration))
                Metric(label: "Length", value: "\(Int(stroke.backswingAngle.rounded()))°")
            }
        }
    }
}

struct StrokeRow: View {
    let stroke: PuttStroke

    var body: some View {
        HStack {
            Text(stroke.tempoRatio, format: .number.precision(.fractionLength(2))).bold().monospacedDigit()
            Spacer()
            Text("\(ms(stroke.backswingDuration)) / \(ms(stroke.downswingDuration))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

struct StatsSummary: View {
    let stats: TempoStats

    var body: some View {
        HStack(spacing: 24) {
            Metric(label: "Putts", value: "\(stats.count)")
            Metric(
                label: "Ratio",
                value: String(format: "%.2f ± %.2f", stats.tempoRatio.mean, stats.tempoRatio.standardDeviation)
            )
            Metric(label: "Total", value: "\(ms(stats.totalDuration.mean)) ± \(ms(stats.totalDuration.standardDeviation))")
        }
    }
}

private struct Metric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
    }
}

func ms(_ seconds: Double) -> String {
    "\(Int((seconds * 1000).rounded())) ms"
}
