import Foundation

public struct DeskLocationFix: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var accuracy: Double
    public var timestamp: Date

    public init(latitude: Double, longitude: Double, accuracy: Double, timestamp: Date = Date()) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.timestamp = timestamp
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite && accuracy.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude) && accuracy >= 0
    }

    public func distance(to other: Self) -> Double {
        let radians = Double.pi / 180
        let lat = (other.latitude - latitude) * radians
        let lon = (other.longitude - longitude) * radians
        let a = pow(sin(lat / 2), 2) + cos(latitude * radians) * cos(other.latitude * radians) * pow(sin(lon / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, a))))
    }
}

public struct DeskLocationAnchor: Codable, Equatable, Sendable {
    public var profileID: UUID
    public var fix: DeskLocationFix
    public var radius: Double

    public init(profileID: UUID, fix: DeskLocationFix, radius: Double = 250) {
        self.profileID = profileID
        self.fix = fix
        self.radius = radius
    }
}

public enum DeskLocationMatch: Equatable {
    case matched(UUID)
    case uncertain
    case outside
    case invalid
}

public enum DeskLocationMatcher {
    /// Accuracy estimates are not guarantees. Reject stale fixes and every
    /// plausible overlap instead of selecting the nearest desk arbitrarily.
    public static func match(_ fix: DeskLocationFix, anchors: [DeskLocationAnchor], now: Date = Date()) -> DeskLocationMatch {
        guard fix.isValid, now.timeIntervalSince(fix.timestamp) <= 60,
              now.timeIntervalSince(fix.timestamp) >= -5 else { return .invalid }
        let valid = anchors.filter { $0.fix.isValid && $0.radius.isFinite && $0.radius > 0 }
        let possible = valid.filter { fix.distance(to: $0.fix) <= $0.radius + fix.accuracy + $0.fix.accuracy }
        guard !possible.isEmpty else { return .outside }
        guard possible.count == 1, let candidate = possible.first,
              fix.distance(to: candidate.fix) + fix.accuracy + candidate.fix.accuracy <= candidate.radius else {
            return .uncertain
        }
        return .matched(candidate.profileID)
    }
}
