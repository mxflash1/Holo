import AppKit
import Combine
import CoreLocation
import HoloCore

@MainActor
final class DeskLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private struct Settings: Codable {
        var enabled = false
        var anchors: [DeskLocationAnchor] = []
    }
    @Published private(set) var enabled = false
    @Published private(set) var anchors: [DeskLocationAnchor] = []
    @Published private(set) var status = "Automatic desk switching is off"
    @Published private(set) var measuredAccuracy: Double?
    @Published private(set) var busy = false
    @Published var radius: Double = 250
    var availableProfiles: () -> Set<UUID> = { [] }
    var selectCandidate: (UUID) -> Bool = { _ in false }
    private let manager = CLLocationManager()
    private let defaults: UserDefaults
    private let key = "deskLocationSettings.v1"
    private var timer: Timer?
    private var timeout: Task<Void, Never>?
    private var confirmation: Task<Void, Never>?
    private var candidate: (id: UUID, timestamp: Date)?
    private var pendingSave: UUID?
    private var measurementOnly = false
    private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        if let data = defaults.data(forKey: key) {
            do {
                let settings = try JSONDecoder().decode(Settings.self, from: data)
                enabled = settings.enabled
                anchors = settings.anchors
            } catch { status = "Saved desk locations could not be read. Automatic switching is off." }
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        for notification in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: notification, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor in
                    guard let self else { return }
                    if note.name == NSWorkspace.willSleepNotification { self.stopRequests() }
                    else if self.enabled { self.startMonitoring() }
                }
            })
        }
    }

    func activate() {
        if enabled { startMonitoring() }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        persist()
        stopRequests()
        if value { startMonitoring() }
        else { status = "Automatic desk switching is off" }
    }

    func checkAccuracy() {
        guard !busy else { return }
        candidate = nil
        confirmation?.cancel()
        measurementOnly = true
        requestFix()
    }

    func saveCurrentLocation(for id: UUID) {
        guard !busy else { return }
        pendingSave = id
        measurementOnly = false
        candidate = nil
        confirmation?.cancel()
        requestFix()
    }

    func removeLocation(for id: UUID) {
        if pendingSave == id { stopRequests(); if enabled { startMonitoring() } }
        anchors.removeAll { $0.profileID == id }
        candidate = nil
        persist()
        status = "Desk location removed"
    }

    private func persist() {
        do { defaults.set(try JSONEncoder().encode(Settings(enabled: enabled, anchors: anchors)), forKey: key) }
        catch { status = "Desk locations could not be saved: \(error.localizedDescription)" }
    }

    private func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.requestFix() }
        }
        timer?.tolerance = 30
        requestFix()
    }

    func stopRequests() {
        timer?.invalidate()
        timer = nil
        timeout?.cancel()
        confirmation?.cancel()
        manager.stopUpdatingLocation()
        busy = false
        pendingSave = nil
        measurementOnly = false
        candidate = nil
    }

    private func requestFix() {
        guard !busy, enabled || pendingSave != nil || measurementOnly else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            status = "Allow Location Services to associate desks with places"
            manager.requestWhenInUseAuthorization()
            return
        case .denied, .restricted:
            status = "Location access is off. Enable Holo in System Settings → Privacy & Security → Location Services."
            pendingSave = nil
            measurementOnly = false
            return
        default: break
        }
        busy = true
        status = pendingSave == nil ? "Checking desk location…" : "Measuring this desk’s location…"
        manager.requestLocation()
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 25_000_000_000) } catch { return }
            guard let self else { return }
            self.manager.stopUpdatingLocation()
            self.busy = false
            self.pendingSave = nil
            self.measurementOnly = false
            self.candidate = nil
            self.status = "Location unavailable. Your desk selection is unchanged."
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.requestFix() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.busy else { return }
            self.timeout?.cancel()
            self.busy = false
            self.pendingSave = nil
            self.measurementOnly = false
            self.candidate = nil
            self.status = "Location unavailable. Your desk selection is unchanged."
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let fix = DeskLocationFix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                  accuracy: location.horizontalAccuracy, timestamp: location.timestamp)
        Task { @MainActor [weak self] in self?.receive(fix) }
    }

    private func receive(_ fix: DeskLocationFix) {
        guard busy else { return }
        timeout?.cancel()
        busy = false
        let validProfiles = availableProfiles()
        let savedID = pendingSave
        let justMeasuring = measurementOnly
        measurementOnly = false
        pendingSave = nil
        guard fix.isValid, (-60...5).contains(fix.timestamp.timeIntervalSinceNow) else {
            candidate = nil
            status = "Location is stale or invalid. Your desk selection is unchanged."
            return
        }
        measuredAccuracy = fix.accuracy
        if justMeasuring {
            status = "Estimated accuracy: ±\(Int(fix.accuracy)) m. No desk location was saved."
            return
        }
        if let id = savedID {
            guard validProfiles.contains(id) else { status = "That desk no longer exists"; return }
            guard fix.accuracy <= min(100, radius / 2) else {
                status = "Location is too imprecise to save (±\(Int(fix.accuracy)) m). Try again at this desk."
                return
            }
            anchors.removeAll { $0.profileID == id }
            anchors.append(DeskLocationAnchor(profileID: id, fix: fix, radius: radius))
            persist()
            status = "Desk location saved (estimated ±\(Int(fix.accuracy)) m)"
            return
        }
        guard enabled else { return }
        let known = anchors.filter { validProfiles.contains($0.profileID) }
        switch DeskLocationMatcher.match(fix, anchors: known) {
        case .matched(let id):
            if let candidate, candidate.id == id, fix.timestamp.timeIntervalSince(candidate.timestamp) >= 5 {
                self.candidate = nil
                status = selectCandidate(id) ? "Desk matched by location" : "Desk match ready. Return to Overview after finishing setup or editing."
            } else {
                if let candidate, candidate.id == id {
                    self.candidate = nil
                    status = "Waiting for a fresh location. Your desk selection is unchanged."
                    return
                }
                candidate = (id, fix.timestamp)
                status = "Confirming desk location…"
                confirmation?.cancel()
                confirmation = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
                    self?.requestFix()
                }
            }
        case .uncertain:
            candidate = nil
            status = "Nearby desks or uncertain location. Choose a desk manually."
        case .outside:
            candidate = nil
            status = known.isEmpty ? "Save a location for each desk to begin" : "No saved place matches. Your desk selection is unchanged."
        case .invalid:
            candidate = nil
            status = "Location is unavailable. Your desk selection is unchanged."
        }
    }
}

import SwiftUI

struct DeskLocationMenu: View {
    @ObservedObject var model: AppModel
    @ObservedObject var service: DeskLocationService

    var body: some View {
        Menu("Desk Locations") {
            Toggle("Switch desks automatically", isOn: Binding(get: { service.enabled }, set: service.setEnabled))
            Button("Check Location Accuracy") { service.checkAccuracy() }
                .disabled(service.busy)
            Text(service.status)
            if let accuracy = service.measuredAccuracy {
                Text("Last estimated accuracy: ±\(Int(accuracy)) m")
            }
            Divider()
            if let profile = model.selectedProfile {
                Button("Save This Location for \(profile.name)") { service.saveCurrentLocation(for: profile.id) }
                    .disabled(service.busy || model.guidedSection != nil || model.isCreatingProfile)
                Picker("Place radius", selection: $service.radius) {
                    ForEach([50.0, 100, 250, 500], id: \.self) { radius in
                        Text("\(Int(radius)) m").tag(radius)
                    }
                }
                Text("Radius applies when saving a location; it is not a measure of accuracy.")
                if let anchor = service.anchors.first(where: { $0.profileID == profile.id }) {
                    Text("Saved radius: \(Int(anchor.radius)) m")
                    Button("Remove Location for \(profile.name)") { service.removeLocation(for: profile.id) }
                }
            }
            Text("Nearby rooms may need manual selection. Manual selection turns automatic switching off.")
        }
    }
}
