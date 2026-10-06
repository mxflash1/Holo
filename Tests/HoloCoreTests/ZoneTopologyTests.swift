import XCTest
@testable import HoloCore

final class ZoneTopologyTests: XCTestCase {
    func testDeskHasExactlyOneZoneOnEachSideOfMacBook() {
        XCTAssertEqual(DeskZone.allCases.count, 2)
        XCTAssertEqual(
            DeskZone.allCases.filter(\.isLeft),
            [.left]
        )
        XCTAssertEqual(
            DeskZone.allCases.filter { !$0.isLeft },
            [.right]
        )
        XCTAssertEqual(DeskZone.allCases.map(\.verticalIndex), [0, 0])
        XCTAssertEqual(DeskZone.allCases.map(\.shortName), ["L", "R"])
        XCTAssertEqual(DeskZone.allCases.map(\.positionName), ["Left", "Right"])
    }

    func testDefaultProfileConfigurationHasOneActionPerZone() throws {
        let classifier = try TrainedTapClassifier.train(positiveExamples: trainingSamples())
        let profile = HoloProfile(
            name: "Two zone desk",
            surfaceDescription: "Wood",
            laptopPositionNote: "Centered",
            classifier: classifier,
            calibration: CalibrationSummary(
                sampleCount: 4,
                samplesPerZone: Array(repeating: 2, count: 2),
                leaveOneOutAccuracy: nil
            )
        )

        XCTAssertEqual(profile.zones.map(\.zone), DeskZone.allCases)
        XCTAssertEqual(profile.zones.count, 2)
    }

    private func trainingSamples() -> [LabeledTap] {
        DeskZone.allCases.flatMap { zone in
            (0..<2).map { index in
                LabeledTap(
                    zone: zone,
                    feature: TapFeatureVector(
                        strategy: .passive,
                        names: ["vertical", "side"],
                        values: [
                            Double(zone.verticalIndex) + Double(index) * 0.01,
                            Double(zone.column) + Double(index) * 0.01
                        ],
                        quality: SignalQuality(
                            signalToNoiseDB: 20,
                            peakAmplitude: 0.1,
                            rmsAmplitude: 0.02,
                            clippingFraction: 0,
                            noiseFloorRMS: 0.001,
                            durationMilliseconds: 90
                        )
                    )
                )
            }
        }
    }
}
