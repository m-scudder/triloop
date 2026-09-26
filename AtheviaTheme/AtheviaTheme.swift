import Foundation
import SwiftUI

/// Presentation only. Never use a theme value when making training decisions.
enum AtheviaTheme: String, CaseIterable, Sendable {
    case classic
    case gaming

    static let preferenceKey = "athevia.gamingThemeEnabled.v1"

    init(gamingEnabled: Bool) {
        self = gamingEnabled ? .gaming : .classic
    }

    static func stored(in defaults: UserDefaults = .standard) -> Self {
        let enabled = defaults.object(forKey: preferenceKey) as? Bool
        return Self(gamingEnabled: enabled ?? false)
    }

    var isGaming: Bool { self == .gaming }

    func color(_ role: GamingPalette.Role, classic: Color) -> Color {
        isGaming ? GamingPalette.color(role) : classic
    }
}

/// Edit ONLY this palette to change Gaming colours across iPhone, Watch and
/// Live Activities. Classic colours remain at their original call sites.
enum GamingPalette {
    enum Role: CaseIterable, Equatable, Sendable {
        case canvas, surface, raisedSurface, border, hero, heroEnd
        case text, secondaryText, accent, onAccent, highlight, achievement
        case running, swimming, cycling, multisport, recovery, rest
        case danger, warning, success
    }

    static func hex(_ role: Role) -> UInt32 {
        switch role {
        case .canvas: 0x160A2D
        case .surface: 0x281245
        case .raisedSurface: 0x43216D
        case .border: 0x8952B6
        case .hero: 0x6B21B0
        case .heroEnd: 0x3B176C
        case .text: 0xFFFAFF
        case .secondaryText: 0xD5C9EC
        case .accent: 0xC4FF47
        case .onAccent: 0x182A04
        case .highlight: 0x4FE5FF
        case .achievement: 0xFFD568
        case .running: 0xFF9B55
        case .swimming: 0x4FE5FF
        case .cycling: 0x65FFB4
        case .multisport: 0xBC8AFF
        case .recovery: 0x70E9E0
        case .rest: 0xB6A9C8
        case .danger: 0xFF939D
        case .warning: 0xFFD568
        case .success: 0x65FFB4
        }
    }

    static func color(_ role: Role) -> Color {
        let value = hex(role)
        return Color(
            .sRGB,
            red: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255,
            blue: Double(value & 255) / 255,
            opacity: 1
        )
    }

    static let heroGradient = LinearGradient(
        colors: [color(.hero), color(.heroEnd)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct AtheviaThemeKey: EnvironmentKey {
    static let defaultValue = AtheviaTheme.classic
}

extension EnvironmentValues {
    var atheviaTheme: AtheviaTheme {
        get { self[AtheviaThemeKey.self] }
        set { self[AtheviaThemeKey.self] = newValue }
    }
}

/// Retains the exact original ShapeStyle in Classic, including materials and
/// semantic system colours. Resolves again when the environment changes.
struct AtheviaAdaptiveStyle<Classic: ShapeStyle>: ShapeStyle {
    let classic: Classic
    let gaming: GamingPalette.Role

    init(_ classic: Classic, gaming: GamingPalette.Role) {
        self.classic = classic
        self.gaming = gaming
    }

    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        guard environment.atheviaTheme.isGaming else { return AnyShapeStyle(classic) }
        if gaming == .hero { return AnyShapeStyle(GamingPalette.heroGradient) }
        return AnyShapeStyle(GamingPalette.color(gaming))
    }
}

struct AtheviaThemeRoot: ViewModifier {
    let theme: AtheviaTheme
    let classicTint: Color

    func body(content: Content) -> some View {
        content
            .environment(\.atheviaTheme, theme)
            #if !os(watchOS)
            .preferredColorScheme(theme.isGaming ? .dark : nil)
            #endif
            .fontDesign(theme.isGaming ? .rounded : .default)
            .tint(theme.color(.accent, classic: classicTint))
            .foregroundStyle(
                theme.color(.text, classic: .primary),
                theme.color(.secondaryText, classic: .secondary)
            )
            .background(theme.isGaming ? GamingPalette.color(.canvas) : Color.clear)
    }
}

private struct AtheviaScreenSurface: ViewModifier {
    @Environment(\.atheviaTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background {
                // Decoration only: never adds hit targets or replaces content.
                LinearGradient(
                    colors: theme.isGaming
                        ? [GamingPalette.color(.heroEnd), GamingPalette.color(.canvas)]
                        : [Color.clear, Color.clear],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            #if os(iOS)
            .toolbarBackground(
                AtheviaAdaptiveStyle(.bar, gaming: .canvas),
                for: .navigationBar, .tabBar
            )
            .toolbarBackground(theme.isGaming ? .visible : .automatic, for: .navigationBar, .tabBar)
            #endif
            #if os(watchOS)
            .containerBackground(AtheviaAdaptiveStyle(Color.black, gaming: .canvas), for: .navigation)
            #endif
    }
}

private struct AtheviaListSurface: ViewModifier {
    @Environment(\.atheviaTheme) private var theme

    func body(content: Content) -> some View {
        content
            #if !os(watchOS)
            .scrollContentBackground(theme.isGaming ? .hidden : .automatic)
            #endif
            .atheviaScreen()
    }
}

private struct AtheviaListRowSurface: ViewModifier {
    @Environment(\.atheviaTheme) private var theme

    func body(content: Content) -> some View {
        content.listRowBackground(theme.isGaming ? GamingPalette.color(.surface) : nil)
    }
}

extension View {
    func atheviaTheme(_ theme: AtheviaTheme, classicTint: Color = .primary) -> some View {
        modifier(AtheviaThemeRoot(theme: theme, classicTint: classicTint))
    }

    func atheviaScreen() -> some View { modifier(AtheviaScreenSurface()) }
    func atheviaList() -> some View { modifier(AtheviaListSurface()) }
    func atheviaListRow() -> some View { modifier(AtheviaListRowSurface()) }
}
