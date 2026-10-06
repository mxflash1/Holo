import Foundation

public enum DeskZone: Int, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case left = 0
    case right

    public var id: Int { rawValue }
    public var verticalIndex: Int { 0 }
    public var row: Int { 0 }
    public var column: Int { rawValue }
    public var isLeft: Bool { self == .left }
    public var positionName: String { displayName }
    public var shortName: String { isLeft ? "L" : "R" }
    public var displayName: String { isLeft ? "Left" : "Right" }
    public var instruction: String {
        "Tap beside the MacBook on the \(isLeft ? "left" : "right"). Spread taps across that side."
    }

}

public enum SensingStrategy: String, CaseIterable, Codable, Sendable, Identifiable {
    case passive
    case active
    case hybrid

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .passive: return "Passive tap acoustics"
        case .active: return "Active acoustic probe"
        case .hybrid: return "Hybrid"
        }
    }

    public var detail: String {
        switch self {
        case .passive:
            return "Uses only the sound and vibration produced by a tap."
        case .active:
            return "Measures how a quiet repeating chirp changes around a tap."
        case .hybrid:
            return "Combines tap acoustics with the chirp response."
        }
    }
}

public enum RejectionReason: String, Codable, Sendable, Equatable {
    case weakSignal
    case lowSignalToNoise
    case clippedSignal
    case outOfDistribution
    case ambiguousZone
    case resemblesNegativeExample
    case schemaMismatch
    case paused

    public var displayName: String {
        switch self {
        case .weakSignal: return "Signal too weak"
        case .lowSignalToNoise: return "Background noise too high"
        case .clippedSignal: return "Signal clipped"
        case .outOfDistribution: return "Unlike calibrated taps"
        case .ambiguousZone: return "Zone ambiguous"
        case .resemblesNegativeExample: return "Recognized non-desk sound"
        case .schemaMismatch: return "Profile is incompatible"
        case .paused: return "Listening paused"
        }
    }
}
