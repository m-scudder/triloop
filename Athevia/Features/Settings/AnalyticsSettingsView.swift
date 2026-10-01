import SwiftUI

struct AnalyticsSettingsView: View {
    private var analytics: ProductAnalytics { .shared }
    @State private var isSendingTest = false

    var body: some View {
        Form {
            Section {
                Toggle("Share usage analytics", isOn: Binding(
                    get: { analytics.consent == .allowed },
                    set: { analytics.setConsent($0 ? .allowed : .declined) }
                ))
                .accessibilityIdentifier("analytics.enabled")
            } footer: {
                Text(AnalyticsPrivacyCopy.summary)
            }
            Section("Your choice") {
                Text("Optional. Your training works the same with this switched off. Switching it off clears unsent events and resets this device's analytics identifier.")
                Text("Events already sent are not removed by this switch. Analytics uses a random identifier on this device and is not connected to your sign-in account.")
            }
            #if DEBUG
            Section("Analytics Debug") {
                Text(analytics.diagnosticSummary)
                    .font(.footnote)
                Text(analytics.deliveryStatus)
                    .font(.footnote)
                Button(isSendingTest ? "Sending…" : "Send test event now") {
                    isSendingTest = true
                    analytics.track(.debugTest)
                    Task { @MainActor in
                        await analytics.flush()?.value
                        isSendingTest = false
                    }
                }
                .disabled(!analytics.isEnabled || isSendingTest)
                .accessibilityIdentifier("analytics.sendTestEvent")
            } footer: {
                Text("In PostHog Activity → Live events, look for analytics_debug_test with environment=development. No health data is included.")
            }
            #endif
        }
        .atheviaList()
        .atheviaScreen()
        .navigationTitle("Usage Analytics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum AnalyticsPrivacyCopy {
    static let summary = "Help improve Athevia by sharing which screens and buttons you use, technical success or failure, and the app version with PostHog. We use a random device-specific analytics identifier. We do not send your name, email, health measurements, workouts, routes, notes or chat messages. We do not record your screen or use this data for advertising."
}

struct AnalyticsConsentView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Help improve Athevia")
                        .font(.title2.bold())
                    Text(AnalyticsPrivacyCopy.summary)
                    Text("This is optional. You can change your choice in Settings → Usage Analytics.")
                        .foregroundStyle(.secondary)
                    Button("Share usage analytics") {
                        ProductAnalytics.shared.setConsent(.allowed)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("analytics.allow")
                    Button("Not now") {
                        ProductAnalytics.shared.setConsent(.declined)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("analytics.decline")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .atheviaScreen()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
