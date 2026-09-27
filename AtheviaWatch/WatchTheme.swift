import SwiftUI

extension WatchWorkoutDiscipline {
    func themedTint(_ theme: AtheviaTheme) -> Color {
        let role: GamingPalette.Role
        switch self {
        case .running: role = .running
        case .swimming: role = .swimming
        case .cycling: role = .cycling
        case .multisport: role = .multisport
        }
        return theme.color(role, classic: sportTint)
    }
}
