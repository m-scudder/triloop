import SwiftData
import SwiftUI

struct RootView: View {
    var storeOutcome: StoreOutcome = .opened
    var autoImporter: WorkoutAutoImporter?

    @State private var hasShownStoreAlert = false
    @AppStorage("automaticallyImportWorkouts") private var automaticallyImport = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") {
                TodayView()
            }
            Tab("Plan", systemImage: "calendar") {
                PlanView()
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis") {
                ProgressOverviewView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .task(id: automaticallyImport) {
            await autoImporter?.setEnabled(automaticallyImport)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, automaticallyImport else { return }
            await autoImporter?.importRecentWeeks()
        }
        .alert("Training data was reset", isPresented: showStoreAlert) {
            Button("OK", role: .cancel) { hasShownStoreAlert = true }
        } message: {
            Text(storeMessage)
        }
    }

    private var showStoreAlert: Binding<Bool> {
        Binding(
            get: { storeOutcome != .opened && !hasShownStoreAlert },
            set: { if !$0 { hasShownStoreAlert = true } }
        )
    }

    private var storeMessage: String {
        switch storeOutcome {
        case .opened:
            ""
        case .rebuilt:
            "TriLoop's database format changed, so your previous plans and reports could not be opened and have been replaced with a fresh week."
        case .inMemory:
            "TriLoop could not write to storage. Anything you record now will be lost when the app closes."
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container)
}
