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
                Text("Events already sent are not removed by this switch. If you sign in while sharing analytics, activity is linked to an opaque account identifier across devices. Turning sharing back on while signed in links new activity to that same account.")
            }
            #if DEBUG
            Section {
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
            } header: {
                Text("Analytics Debug")
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
    static let prompt = "Share screen views and button taps with PostHog to improve Athevia. If you sign in, we link this activity across your devices using an opaque account ID. No health records, name or email are sent. Optional—change this in Settings."
    static let summary = "Help improve Athevia by sharing which screens and buttons you use, technical success or failure, and the app version with PostHog. Guests use a random installation identifier. If you sign in, we link earlier guest activity and future activity to an opaque account identifier across devices. We do not send your name, email, health measurements, workouts, routes, notes or chat messages. We do not record your screen or use this data for advertising."
}
