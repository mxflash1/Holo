import XCTest
@testable import HoloCore

final class DeskLocationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func fix(_ longitude: Double = 0, accuracy: Double = 20, age: Double = 0) -> DeskLocationFix {
        DeskLocationFix(latitude: 0, longitude: longitude, accuracy: accuracy, timestamp: now.addingTimeInterval(-age))
    }

    func testDistinctAddressesMatchOnlyTheContainingPlace() {
        let home = DeskLocationAnchor(profileID: UUID(), fix: fix())
        let office = DeskLocationAnchor(profileID: UUID(), fix: fix(0.01))
        XCTAssertEqual(DeskLocationMatcher.match(fix(), anchors: [home, office], now: now), .matched(home.profileID))
        XCTAssertEqual(DeskLocationMatcher.match(fix(0.01), anchors: [home, office], now: now), .matched(office.profileID))
    }

    func testTwoRoomsNeverChooseNearestArbitrarily() {
        let desks = [0.0, 0.0001].map { DeskLocationAnchor(profileID: UUID(), fix: fix($0)) }
        XCTAssertEqual(DeskLocationMatcher.match(fix(), anchors: desks, now: now), .uncertain)
    }

    func testAccuracyIncludesUncertaintyOfSavedAnchorAndCurrentReading() {
        let anchor = DeskLocationAnchor(profileID: UUID(), fix: fix(accuracy: 75))
        XCTAssertEqual(DeskLocationMatcher.match(fix(accuracy: 200), anchors: [anchor], now: now), .uncertain)
        XCTAssertEqual(DeskLocationMatcher.match(fix(accuracy: 25), anchors: [anchor], now: now), .matched(anchor.profileID))
    }

    func testPossibleOverlapBlocksEvenIfOneAnchorContainsTheReading() {
        let near = DeskLocationAnchor(profileID: UUID(), fix: fix())
        let fringe = DeskLocationAnchor(profileID: UUID(), fix: fix(0.0024))
        XCTAssertEqual(DeskLocationMatcher.match(fix(), anchors: [near, fringe], now: now), .uncertain)
    }

    func testStaleFutureNegativeAndNonfiniteFixesAreRejected() {
        let anchor = DeskLocationAnchor(profileID: UUID(), fix: fix())
        for reading in [fix(age: 61), fix(age: -6), fix(accuracy: -1), fix(accuracy: .infinity), fix(.nan)] {
            XCTAssertEqual(DeskLocationMatcher.match(reading, anchors: [anchor], now: now), .invalid)
        }
    }

    func testOutsideAndNoAnchorsDoNotSelectAProfile() {
        let anchor = DeskLocationAnchor(profileID: UUID(), fix: fix())
        XCTAssertEqual(DeskLocationMatcher.match(fix(0.01), anchors: [anchor], now: now), .outside)
        XCTAssertEqual(DeskLocationMatcher.match(fix(), anchors: [], now: now), .outside)
    }

    func testAnchorPersistenceKeepsProfileAndEstimatedAccuracy() throws {
        let original = DeskLocationAnchor(profileID: UUID(), fix: fix(accuracy: 57), radius: 100)
        let loaded = try JSONDecoder().decode(DeskLocationAnchor.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(loaded, original)
    }
}
