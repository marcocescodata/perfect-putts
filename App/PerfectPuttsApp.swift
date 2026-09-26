import SwiftData
import SwiftUI

@main
struct PerfectPuttsApp: App {
    var body: some Scene {
        WindowGroup {
            PracticeView()
        }
        .modelContainer(for: [PracticeSession.self, StrokeRecord.self])
    }
}
