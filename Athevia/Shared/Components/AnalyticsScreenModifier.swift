import SwiftUI

private struct AnalyticsScreenModifier: ViewModifier {
    let screen: AnalyticsScreen
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !appeared else { return }
                appeared = true
                ProductAnalytics.shared.track(.screenViewed(screen))
            }
            .onDisappear { appeared = false }
            .onChange(of: ProductAnalytics.shared.consent) { _, consent in
                if appeared, consent == .allowed {
                    ProductAnalytics.shared.track(.screenViewed(screen))
                }
            }
    }
}

extension View {
    func analyticsScreen(_ screen: AnalyticsScreen) -> some View {
        modifier(AnalyticsScreenModifier(screen: screen))
    }
}
