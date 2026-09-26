import Charts
import PuttCore
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PracticeSession.startedAt, order: .reverse) private var sessions: [PracticeSession]

    var body: some View {
        List {
            ForEach(sessions) { session in
                NavigationLink {
                    SessionDetailView(session: session)
                } label: {
                    VStack(alignment: .leading) {
                        Text(session.startedAt, format: .dateTime.day().month().hour().minute())
                        if let stats = session.stats {
                            Text(String(format: "%d putts · %.2f ± %.2f", stats.count, stats.tempoRatio.mean, stats.tempoRatio.standardDeviation))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { offsets in
                offsets.map { sessions[$0] }.forEach(modelContext.delete)
            }
        }
        .overlay {
            if sessions.isEmpty { ContentUnavailableView("No sessions yet", systemImage: "figure.golf") }
        }
        .navigationTitle("History")
    }
}

struct SessionDetailView: View {
    let session: PracticeSession

    var body: some View {
        let strokes = session.orderedStrokes
        List {
            if let stats = session.stats {
                Section { StatsSummary(stats: stats) }
            }
            Section("Tempo ratio by putt") {
                Chart {
                    RuleMark(y: .value("Target", 2.0))
                        .foregroundStyle(.green.opacity(0.5))
                        .lineStyle(StrokeStyle(dash: [4, 4]))
                    ForEach(Array(strokes.enumerated()), id: \.offset) { index, stroke in
                        LineMark(x: .value("Putt", index + 1), y: .value("Ratio", stroke.metrics.tempoRatio))
                        PointMark(x: .value("Putt", index + 1), y: .value("Ratio", stroke.metrics.tempoRatio))
                    }
                }
                .frame(height: 200)
            }
            Section("Putts") {
                ForEach(strokes) { StrokeRow(stroke: $0.metrics) }
            }
        }
        .navigationTitle(session.startedAt.formatted(date: .abbreviated, time: .shortened))
    }
}
