import PuttCore
import SwiftData
import SwiftUI

struct PracticeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var motion = HeadphoneMotionService()
    @State private var session: PracticeSession?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ConnectionBadge(isConnected: motion.isConnected)
                    if let error = motion.errorMessage {
                        Text(error).foregroundStyle(.red)
                    }
                }

                if let session {
                    Section {
                        PhaseBanner(phase: motion.phase)
                    }
                    if let last = session.orderedStrokes.last {
                        Section("Last putt") { StrokeSummary(stroke: last.metrics) }
                    }
                    if let stats = session.stats {
                        Section("This session") { StatsSummary(stats: stats) }
                    }
                    Section("Putts") {
                        ForEach(session.orderedStrokes.reversed()) { StrokeRow(stroke: $0.metrics) }
                    }
                }
            }
            .navigationTitle("Perfect Putts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink("History") { HistoryView() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(session == nil ? "Start session" : "End session", action: toggleSession)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(session == nil ? .green : .red)
                    .padding()
            }
        }
        .onAppear {
            motion.onStroke = { detected in
                guard let session else { return }
                let record = StrokeRecord(detected)
                modelContext.insert(record)
                record.session = session
            }
        }
    }

    private func toggleSession() {
        if let session {
            motion.stop()
            session.endedAt = .now
            if session.strokes.isEmpty { modelContext.delete(session) }
            self.session = nil
        } else {
            let new = PracticeSession()
            modelContext.insert(new)
            session = new
            motion.start()
        }
    }
}

private struct ConnectionBadge: View {
    let isConnected: Bool

    var body: some View {
        Label(
            isConnected ? "AirPods connected" : "Waiting for AirPods",
            systemImage: isConnected ? "airpodspro" : "airpodspro.chargingcase.wireless"
        )
        .foregroundStyle(isConnected ? .green : .secondary)
    }
}

private struct PhaseBanner: View {
    let phase: StrokeDetector.Phase

    var body: some View {
        switch phase {
        case .waitingForAddress:
            Label("Settle over the ball", systemImage: "hand.raised")
        case .ready:
            Label("Ready — putt when you like", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .inStroke:
            Label("Recording…", systemImage: "record.circle").foregroundStyle(.orange)
        }
    }
}
