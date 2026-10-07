import Foundation

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case desks
    case sounds
    case locations
    case settings
    case live
    case calibrate
    case actions
    case evaluate
    case diagnostics

    static let primary: [AppSection] = [.live, .desks, .sounds, .locations, .actions]
    static let advanced: [AppSection] = [.diagnostics]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: return "Overview"
        case .desks: return "My Desks"
        case .sounds: return "Shared Sounds"
        case .locations: return "Locations"
        case .settings: return "Settings"
        case .calibrate: return "Calibration"
        case .diagnostics: return "Diagnostics"
        case .evaluate: return "Accuracy Test"
        case .actions: return "Actions"
        }
    }

    var symbol: String {
        switch self {
        case .live: return "rectangle.split.2x1.fill"
        case .desks: return "macbook"
        case .sounds: return "waveform.badge.minus"
        case .locations: return "location"
        case .settings: return "gearshape"
        case .calibrate: return "scope"
        case .diagnostics: return "waveform.path.ecg"
        case .evaluate: return "checkmark.seal"
        case .actions: return "slider.horizontal.3"
        }
    }
}
