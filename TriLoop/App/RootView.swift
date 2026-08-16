import SwiftData
import SwiftUI

struct RootView: View {
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
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container)
}
