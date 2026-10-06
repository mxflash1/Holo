import XCTest
@testable import HoloCore

final class PersistenceTests: XCTestCase {
    func testFourZoneProfileIsSkippedWithoutRewritingItsData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProfileStore(directory: directory)
        let original = Data(#"{"version":3,"zones":[{"zone":0},{"zone":1},{"zone":2},{"zone":3}]}"#.utf8)
        let url = directory.appendingPathComponent("old-desk.json")
        try original.write(to: url)
        XCTAssertTrue(try store.loadAll().isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testProfileRoundTripDoesNotStoreAudio() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try ProfileStore(directory: temporary)
        let classifier = try TrainedTapClassifier.train(positiveExamples: samples())
        var zones = DeskZone.allCases.map { ZoneConfiguration(zone: $0) }
        zones[DeskZone.left.rawValue].action = ZoneActionConfiguration(
            kind: .copyText,
            text: "Focus mode"
        )
        zones[DeskZone.right.rawValue].action = ZoneActionConfiguration(
            kind: .openApplication,
            text: "Notes",
            bookmarkData: Data([0x48, 0x4F, 0x4C, 0x4F])
        )
        let profile = HoloProfile(
            name: "Oak desk",
            surfaceDescription: "Solid oak",
            laptopPositionNote: "Centered",
            classifier: classifier,
            calibration: CalibrationSummary(
                sampleCount: DeskZone.allCases.count * 2,
                samplesPerZone: Array(repeating: 2, count: DeskZone.allCases.count),
                leaveOneOutAccuracy: 1
            ),
            zones: zones
        )
        try store.save(profile)
        let loaded = try XCTUnwrap(store.loadAll().first)
        XCTAssertEqual(loaded.id, profile.id)
        XCTAssertEqual(loaded.name, "Oak desk")
        XCTAssertEqual(loaded.zones.map(\.zone), DeskZone.allCases)
        XCTAssertEqual(loaded.action(for: .left).kind, .copyText)
        XCTAssertEqual(loaded.action(for: .left).text, "Focus mode")
        XCTAssertEqual(loaded.action(for: .right).kind, .openApplication)
        XCTAssertEqual(loaded.action(for: .right).bookmarkData, Data([0x48, 0x4F, 0x4C, 0x4F]))

        let files = try FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.pathExtension, "json")

        let persistedURL = try XCTUnwrap(files.first)
        let persistedData = try Data(contentsOf: persistedURL)
        let persistedJSON = try XCTUnwrap(String(data: persistedData, encoding: .utf8))
        XCTAssertFalse(persistedJSON.contains("\"channels\""))
        XCTAssertFalse(persistedJSON.contains("\"onsetOffset\""))
        XCTAssertFalse(persistedJSON.contains("\"streamSampleIndex\""))
        XCTAssertFalse(persistedData.starts(with: Data("RIFF".utf8)))
    }

    func testLegacySixZoneProfileIsIgnoredBeforeZoneDecoding() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try ProfileStore(directory: temporary)
        let classifier = try TrainedTapClassifier.train(positiveExamples: samples())
        var profile = HoloProfile(
            name: "Legacy desk",
            surfaceDescription: "Wood",
            laptopPositionNote: "Centered",
            classifier: classifier,
            calibration: CalibrationSummary(
                sampleCount: DeskZone.allCases.count * 2,
                samplesPerZone: Array(repeating: 2, count: DeskZone.allCases.count),
                leaveOneOutAccuracy: nil
            )
        )
        profile.version = HoloProfile.currentVersion - 1

        try store.save(profile)

        XCTAssertTrue(try store.loadAll().isEmpty)
    }

    func testLegacyNineZoneValuesAreSkippedBeforeCurrentEnumDecoding() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try ProfileStore(directory: temporary)
        let legacy = temporary.appendingPathComponent("legacy-nine-zone.json")
        try Data(#"{"version":1,"zones":[{"zone":8}]}"#.utf8).write(to: legacy)

        XCTAssertTrue(try store.loadAll().isEmpty)
    }

    func testCorruptProfileIsReportedInsteadOfSilentlyIgnored() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try ProfileStore(directory: temporary)
        let corrupt = temporary.appendingPathComponent("corrupt.json")
        try Data("{ not valid json".utf8).write(to: corrupt)

        XCTAssertThrowsError(try store.loadAll())
    }

    func testCurrentProfileWithMissingZoneIsReported() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try ProfileStore(directory: temporary)
        let classifier = try TrainedTapClassifier.train(positiveExamples: samples())
        var profile = HoloProfile(
            name: "Incomplete desk",
            surfaceDescription: "Wood",
            laptopPositionNote: "Centered",
            classifier: classifier,
            calibration: CalibrationSummary(
                sampleCount: DeskZone.allCases.count * 2,
                samplesPerZone: Array(repeating: 2, count: DeskZone.allCases.count),
                leaveOneOutAccuracy: 1
            )
        )
        profile.zones.removeLast()
        try store.save(profile)

        XCTAssertThrowsError(try store.loadAll()) { error in
            XCTAssertEqual(
                error as? ProfileStoreError,
                .invalidCurrentTopology("\(profile.id.uuidString).json")
            )
        }
    }

    func testCurrentProfileWithIncompleteClassifierIsReported() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try ProfileStore(directory: temporary)
        let classifier = try TrainedTapClassifier.train(positiveExamples: samples())
        var profile = HoloProfile(
            name: "Damaged classifier",
            surfaceDescription: "Wood",
            laptopPositionNote: "Centered",
            classifier: classifier,
            calibration: CalibrationSummary(
                sampleCount: DeskZone.allCases.count * 2,
                samplesPerZone: Array(repeating: 2, count: DeskZone.allCases.count),
                leaveOneOutAccuracy: 1
            )
        )
        profile.classifier.positiveExamples.removeAll { $0.zone == .right }
        try store.save(profile)

        XCTAssertThrowsError(try store.loadAll()) { error in
            XCTAssertEqual(
                error as? ProfileStoreError,
                .invalidCurrentClassifier("\(profile.id.uuidString).json")
            )
        }
    }

    func testCurrentProfileWithMismatchedCalibrationSummaryIsReported() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try ProfileStore(directory: temporary)
        let classifier = try TrainedTapClassifier.train(positiveExamples: samples())
        let profile = HoloProfile(
            name: "Damaged summary",
            surfaceDescription: "Wood",
            laptopPositionNote: "Centered",
            classifier: classifier,
            calibration: CalibrationSummary(
                sampleCount: DeskZone.allCases.count * 2 + 1,
                samplesPerZone: Array(repeating: 2, count: DeskZone.allCases.count),
                leaveOneOutAccuracy: 1
            )
        )
        try store.save(profile)

        XCTAssertThrowsError(try store.loadAll()) { error in
            XCTAssertEqual(
                error as? ProfileStoreError,
                .invalidCurrentCalibration("\(profile.id.uuidString).json")
            )
        }
    }

    func testWaveWriterProducesFloatWAVHeader() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try WaveFileWriter.write(channels: [[0, 0.25, -0.25]], sampleRate: 48_000, to: url)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(data.count, 44 + 3 * 4)
    }

    func testEvaluationStoreRoundTripsJSONAndCSV() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try EvaluationStore(directory: temporary)
        let profileID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let decision = ClassificationDecision(
            zone: .right,
            confidence: 0.88,
            signalStrength: 0.72,
            zoneDistances: [],
            rejectionReason: nil
        )
        let report = EvaluationReport(
            profileID: profileID,
            profileName: "Oak",
            strategy: .passive,
            startedAt: timestamp.addingTimeInterval(-10),
            completedAt: timestamp,
            records: [EvaluationRecord(
                expectedZone: .right,
                decision: decision,
                responseLatencyMilliseconds: 123,
                capturedAt: timestamp
            )]
        )

        let jsonURL = try store.save(report)
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: jsonURL.deletingPathExtension().appendingPathExtension("csv").path
        ))

        let loaded = try XCTUnwrap(store.loadAll().first)
        XCTAssertEqual(loaded.profileID, profileID)
        XCTAssertEqual(loaded.profileName, "Oak")
        XCTAssertEqual(loaded.topologyZoneCount, DeskZone.allCases.count)
        XCTAssertEqual(loaded.records.count, 1)
        XCTAssertEqual(loaded.records.first?.predictedZone, .right)
        XCTAssertEqual(loaded.records.first?.responseLatencyMilliseconds, 123)
    }

    func testEvaluationStoreSkipsReportsFromOlderTopologies() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try EvaluationStore(directory: temporary)
        let oldReport = EvaluationReport(
            topologyZoneCount: 6,
            profileName: "Old six-zone desk",
            strategy: .passive,
            startedAt: Date(),
            records: []
        )
        try oldReport.jsonData().write(to: temporary.appendingPathComponent("old.json"))

        XCTAssertTrue(try store.loadAll().isEmpty)
    }

    func testApproachComparisonRejectsObsoleteTopology() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try ApproachComparisonStore(fileURL: url)
        let score = ApproachScore(
            strategy: .passive,
            crossValidationAccuracy: 0.8,
            rejectionRate: 0.1,
            medianProcessingLatencyMilliseconds: 3,
            sampleCount: 18
        )

        try store.save(ApproachComparison(
            scores: [score],
            selectedStrategy: .passive,
            measuredAt: Date(),
            topologyZoneCount: 9
        ))
        XCTAssertNil(try store.load())

        let profileID = UUID()
        let current = ApproachComparison(
            scores: [score],
            selectedStrategy: .passive,
            measuredAt: Date(),
            profileID: profileID
        )
        try store.save(current)
        XCTAssertEqual(try store.load()?.topologyZoneCount, DeskZone.allCases.count)
        XCTAssertEqual(try store.load()?.profileID, profileID)
    }

    func testSharedRejectionMigrationDeduplicatesAndSurvivesDeskDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profiles = try ProfileStore(directory: directory.appendingPathComponent("Profiles"))
        let positives = samples()
        var typing = LabeledTap(zone: nil, negativeLabel: "Typing", feature: positives[0].feature)
        typing.feature.capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let classifier = try TrainedTapClassifier.train(positiveExamples: positives, negativeExamples: [typing])
        let first = HoloProfile(name: "Home", surfaceDescription: "Wood", laptopPositionNote: "Center",
            classifier: classifier, calibration: CalibrationSummary(sampleCount: positives.count,
                samplesPerZone: [2, 2], leaveOneOutAccuracy: nil))
        var second = first
        second.id = UUID()
        second.name = "School"
        try profiles.save(first)
        try profiles.save(second)
        let shared = SharedRejectionStore(fileURL: directory.appendingPathComponent("shared.json"))
        let migrated = try shared.loadOrMigrate(profiles: profiles.loadAll())
        XCTAssertEqual(migrated.samples.map(\.id), [typing.id])
        try profiles.delete(first)
        try profiles.delete(second)
        XCTAssertEqual(try shared.loadOrMigrate(profiles: []).samples, [typing])
        let trained = try TrainedTapClassifier.train(positiveExamples: positives,
            negativeExamples: migrated.compatible(with: positives[0].feature))
        XCTAssertEqual(trained.positiveExamples, positives)
        XCTAssertEqual(trained.negativeExamples, [typing])
    }

    func testClearedSharedSoundsStayClearedAndOtherStrategiesArePreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let feature = samples()[0].feature
        let typing = LabeledTap(zone: nil, negativeLabel: "Typing", feature: feature)
        var active = typing
        active.id = UUID()
        active.feature.strategy = .active
        var otherSchema = typing
        otherSchema.id = UUID()
        otherSchema.feature.names = ["other-x", "other-y"]
        var library = SharedRejectionLibrary(samples: [typing, active, otherSchema])
        XCTAssertEqual(library.compatible(with: feature), [typing])
        library.replaceCompatible(with: feature, samples: [])
        XCTAssertTrue(library.compatible(with: feature).isEmpty)
        XCTAssertEqual(Set(library.samples.map(\.id)), Set([active.id, otherSchema.id]))
        let store = SharedRejectionStore(fileURL: directory.appendingPathComponent("shared.json"))
        try store.save(library)
        let positives = samples()
        let old = HoloProfile(name: "Old snapshot", surfaceDescription: "Wood", laptopPositionNote: "Center",
            classifier: try TrainedTapClassifier.train(positiveExamples: positives, negativeExamples: [typing]),
            calibration: CalibrationSummary(sampleCount: positives.count, samplesPerZone: [2, 2], leaveOneOutAccuracy: nil))
        XCTAssertTrue(try store.loadOrMigrate(profiles: [old]).compatible(with: feature).isEmpty)
    }

    func testSharedSoundsExcludeDeskTapsAndMalformedFeatures() {
        let positive = samples()[0]
        var invalid = LabeledTap(zone: nil, negativeLabel: "Typing", feature: positive.feature)
        invalid.feature.values = [.nan, 0]
        XCTAssertTrue(SharedRejectionLibrary(samples: [positive, invalid]).samples.isEmpty)
    }

    private func samples() -> [LabeledTap] {
        DeskZone.allCases.flatMap { zone in
            (0..<2).map { index in
                LabeledTap(
                    zone: zone,
                    feature: TapFeatureVector(
                        strategy: .passive,
                        names: ["x", "y"],
                        values: [Double(zone.row) + Double(index) * 0.01, Double(zone.column) - Double(index) * 0.01],
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
