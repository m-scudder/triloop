import Foundation
import SwiftUI

/// Presentation only. Never use a theme value when making training decisions.
struct AtheviaTheme: Equatable, Sendable {
    let isGaming: Bool
    let palette: GamingPalette
    static let classic = Self(gamingEnabled: false)
    static let gaming = Self(gamingEnabled: true)

    static let preferenceKey = "athevia.gamingThemeEnabled.v1"

    init(gamingEnabled: Bool, palette: GamingPalette = .neon) {
        // Preview-only until the palette is ready for public release.
        #if DEBUG
        isGaming = gamingEnabled
        #else
        isGaming = false
        #endif
        self.palette = palette
    }

    static func stored(in defaults: UserDefaults = .standard) -> Self {
        let enabled = defaults.object(forKey: preferenceKey) as? Bool
        return Self(gamingEnabled: enabled ?? false, palette: GamingPalette.stored(in: defaults))
    }

    func color(_ role: GamingPalette.Role, classic: Color) -> Color {
        isGaming ? palette.color(role) : classic
    }
}

/// Edit ONLY this palette to change Gaming colours across iPhone, Watch and
/// Live Activities. Classic colours remain at their original call sites.
enum GamingPalette: String, CaseIterable, Identifiable, Sendable {
    case neon, ocean, ember, aurora, midnight, rose, cobalt, graphite

    static let preferenceKey = "athevia.gamingPalette.v1"
    var id: String { rawValue }
    static func resolve(_ rawValue: String?) -> Self {
        rawValue.flatMap(Self.init(rawValue:)) ?? .neon
    }
    static func stored(in defaults: UserDefaults = .standard) -> Self {
        resolve(defaults.string(forKey: preferenceKey))
    }
    var name: String {
        switch self {
        case .neon: "Neon Arcade"
        case .ocean: "Ocean Quest"
        case .ember: "Ember Arena"
        case .aurora: "Aurora Night"
        case .midnight: "Midnight Gold"
        case .rose: "Rose Pixel"
        case .cobalt: "Cobalt Rush"
        case .graphite: "Graphite Ice"
        }
    }
    var summary: String {
        switch self {
        case .neon: "Violet · Lime · Cyan"
        case .ocean: "Navy · Aqua · Gold"
        case .ember: "Burgundy · Peach · Gold"
        case .aurora: "Forest · Mint · Lavender"
        case .midnight: "Indigo · Gold · Ice"
        case .rose: "Plum · Pink · Mint"
        case .cobalt: "Blue · Sky · Coral"
        case .graphite: "Charcoal · Ice · Lime"
        }
    }

    enum Role: CaseIterable, Hashable, Sendable {
        case canvas, surface, raisedSurface, border, hero, heroEnd
        case text, secondaryText, accent, onAccent, highlight, achievement
        case running, swimming, cycling, multisport, recovery, rest
        case danger, warning, success
    }

    func hex(_ role: Role) -> UInt32 {
        // All preset values live here; sport and status colours stay consistent.
        let surfaces: [UInt32]
        switch self {
        case .neon: surfaces = [0x160A2D, 0x281245, 0x43216D, 0x8952B6, 0x6B21B0, 0x3B176C, 0xC4FF47, 0x182A04, 0x4FE5FF]
        case .ocean: surfaces = [0x071726, 0x102C42, 0x1B4058, 0x437C96, 0x125477, 0x102C42, 0x65F4E0, 0x042E2A, 0xFFD568]
        case .ember: surfaces = [0x210D19, 0x361827, 0x512636, 0xA75E73, 0x762B43, 0x361827, 0xFFBA87, 0x361507, 0xFFD568]
        case .midnight: surfaces = [0x101225, 0x202440, 0x343956, 0x717BA6, 0x393D70, 0x202440, 0xFFD568, 0x322303, 0x9CE8FF]
        case .rose: surfaces = [0x210F24, 0x361C39, 0x502B50, 0xA26699, 0x702D68, 0x361C39, 0xFFACE0, 0x380D2B, 0x8CF4CD]
        case .cobalt: surfaces = [0x0B142E, 0x172B4C, 0x283E61, 0x617FAE, 0x234E85, 0x172B4C, 0x8EDCFF, 0x062B40, 0xFFB5A2]
        case .graphite: surfaces = [0x14171C, 0x252B33, 0x3A414C, 0x7D8797, 0x444D5E, 0x252B33, 0xD3EDFF, 0x172C3A, 0xC4FF47]
        case .aurora: surfaces = [0x091D1C, 0x14312E, 0x23453E, 0x50897A, 0x24574F, 0x14312E, 0x9FF5B6, 0x0A301B, 0xD7B5FF]
        }
        switch role {
        case .canvas: return surfaces[0]
        case .surface: return surfaces[1]
        case .raisedSurface: return surfaces[2]
        case .border: return surfaces[3]
        case .hero: return surfaces[4]
        case .heroEnd: return surfaces[5]
        case .accent: return surfaces[6]
        case .onAccent: return surfaces[7]
        case .highlight: return surfaces[8]
        default: break
        }
        return Self.baseHex(role)
    }

    // Default-palette helpers retained for callers that explicitly need Neon.
    static func hex(_ role: Role) -> UInt32 { neon.hex(role) }
    static func color(_ role: Role) -> Color { neon.color(role) }

    private static func baseHex(_ role: Role) -> UInt32 {
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
        case .swimming: 0x38A7FF
        case .cycling: 0x65FFB4
        case .multisport: 0xBC8AFF
        case .recovery: 0xFFE45C
        case .rest: 0xB6A9C8
        case .danger: 0xFF939D
        case .warning: 0xFFD568
        case .success: 0x65FFB4
        }
    }

    func color(_ role: Role) -> Color {
        let value = hex(role)
        return Color(
            .sRGB,
            red: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255,
            blue: Double(value & 255) / 255,
            opacity: 1
        )
    }

    var heroGradient: LinearGradient { LinearGradient(
        colors: [color(.hero), color(.heroEnd)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    ) }
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
        if gaming == .hero { return AnyShapeStyle(environment.atheviaTheme.palette.heroGradient) }
        return AnyShapeStyle(environment.atheviaTheme.palette.color(gaming))
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
            .background(theme.isGaming ? theme.palette.color(.canvas) : Color.clear)
    }
}

private struct AtheviaScreenSurface: ViewModifier {
    @Environment(\.atheviaTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                // Decoration only: never adds hit targets or replaces content.
                LinearGradient(
                    colors: theme.isGaming
                        ? [theme.palette.color(.heroEnd), theme.palette.color(.canvas)]
                        : [Color.clear, Color.clear],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            #if os(iOS)
            // Navigation chrome is intentionally fixed to black across the app.
            // Using the system .bar material made the same toolbar appear grey
            // in some light/dark-mode combinations.
            .toolbarBackground(
                Color.black,
                for: .navigationBar
            )
            .toolbarBackground(
                .visible,
                for: .navigationBar
            )
            .toolbarColorScheme(
                .dark,
                for: .navigationBar
            )
            .toolbarBackground(
                theme.isGaming
                    ? AnyShapeStyle(theme.palette.color(.canvas))
                    : AnyShapeStyle(.bar),
                for: .tabBar
            )
            .toolbarBackground(
                theme.isGaming ? .visible : .automatic,
                for: .tabBar
            )
            .toolbarColorScheme(
                theme.isGaming ? .dark : colorScheme,
                for: .tabBar
            )
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
        content.listRowBackground(theme.isGaming ? theme.palette.color(.surface) : nil)
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
