import HoloCore
import SwiftUI

struct DesksView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("My Desks").font(.title.weight(.semibold))
                Spacer()
                Button("New Desk", systemImage: "plus", action: model.prepareNewProfile).holoPrimaryButton()
            }
            Text("Each desk keeps its own left and right calibration. Your sounds to ignore are shared.")
                .foregroundStyle(.secondary)
            if model.profiles.isEmpty {
                ContentUnavailableView("Add your first desk", systemImage: "macbook", description: Text("Choose New Desk to name it and calibrate its taps."))
            } else {
                Form {
                    ForEach(model.profiles) { profile in
                        Section {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.name).font(.headline)
                                    Text(profile.surfaceDescription).foregroundStyle(.secondary)
                                    if !profile.laptopPositionNote.isEmpty {
                                        Text(profile.laptopPositionNote).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if model.selectedProfileID == profile.id {
                                    Label("Selected", systemImage: "checkmark").foregroundStyle(.secondary)
                                } else { Button("Select") { model.selectProfile(profile.id) } }
                            }
                            HStack {
                                Button("Calibrate") { model.selectProfile(profile.id); model.prepareRecalibration() }
                                Button("Accuracy Test") { model.selectProfile(profile.id); model.section = .evaluate }
                                Button("Actions") { model.selectProfile(profile.id); model.section = .actions }
                                Button("Location") { model.selectProfile(profile.id); model.section = .locations }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }.formStyle(.grouped)
            }
        }.padding(24)
    }
}

struct SharedSoundsView: View {
    @ObservedObject var model: AppModel
    @State private var clearLabel: String?
    private let labels = ["Talking", "Typing", "Mouse clicks", "Laptop touch", "Background noise"]
    private var samples: [LabeledTap] { model.sharedSoundDraft ?? model.sharedRejections.samples }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Shared Sounds").font(.title.weight(.semibold))
            Text("Teach Holo which sounds to ignore once, then reuse them at every desk. Desk taps are calibrated separately.")
                .foregroundStyle(.secondary)
            Form {
                Section("Sounds to ignore") {
                    ForEach(labels, id: \.self) { label in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(label)
                                Text("\(samples.filter { $0.negativeLabel == label }.count) examples")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.sharedCaptureLabel == label {
                                Button("Stop Recording", action: model.stopSharedSoundCapture)
                            } else {
                                Button("Record") { model.startSharedSoundCapture(label) }
                                    .disabled(model.sharedCaptureLabel != nil)
                            }
                            Button("Clear") { clearLabel = label }
                                .disabled(model.sharedSoundDraft != nil || !samples.contains { $0.negativeLabel == label })
                        }
                    }
                }
                Section {
                    Text("Only acoustic features are saved. New examples use \(model.targetStrategy.displayName.lowercased()); incompatible sensing formats stay separate.")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.sharedCaptureLabel != nil {
                        Label("Make the selected sound naturally. Desk actions are paused while recording.", systemImage: "mic.fill")
                    }
                    if model.sharedSoundDraft != nil {
                        HStack {
                            Button("Save Shared Sounds", action: model.saveSharedSounds).holoPrimaryButton()
                            Button("Cancel", action: model.cancelSharedSounds)
                        }
                    }
                }
            }.formStyle(.grouped)
        }.padding(24)
        .confirmationDialog("Clear \(clearLabel ?? "") examples from all desks?", isPresented: Binding(
            get: { clearLabel != nil }, set: { if !$0 { clearLabel = nil } }
        ), titleVisibility: .visible) {
            Button("Clear Examples", role: .destructive) {
                if let label = clearLabel { model.clearSharedSounds(label: label) }
                clearLabel = nil
            }
            Button("Cancel", role: .cancel) { clearLabel = nil }
        }
    }
}

struct LocationsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var service: DeskLocationService
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Locations").font(.title.weight(.semibold))
            Text("Switch desks automatically when you move between places. Choose manually when nearby desks overlap.")
                .foregroundStyle(.secondary)
            Form {
                Section("Automatic switching") {
                    Toggle("Switch desks by location", isOn: Binding(get: { service.enabled }, set: service.setEnabled))
                    Text(service.status).foregroundStyle(.secondary)
                    HStack {
                        if let accuracy = service.measuredAccuracy { Text("Last estimated accuracy: ±\(Int(accuracy)) m") }
                        Spacer()
                        Button("Check Accuracy", action: service.checkAccuracy).disabled(service.busy)
                    }
                }
                Section("Saved places") {
                    if model.profiles.isEmpty { Text("Create a desk before adding its location.").foregroundStyle(.secondary) }
                    ForEach(model.profiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name).font(.headline)
                                if let anchor = service.anchors.first(where: { $0.profileID == profile.id }) {
                                    Text("Saved • \(Int(anchor.radius)) m place radius").font(.caption).foregroundStyle(.secondary)
                                } else { Text("No location saved").font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button("Use Current Location") { service.saveCurrentLocation(for: profile.id) }.disabled(service.busy)
                            if service.anchors.contains(where: { $0.profileID == profile.id }) {
                                Button("Remove") { service.removeLocation(for: profile.id) }
                            }
                        }
                    }
                    Picker("Radius for the next saved place", selection: $service.radius) {
                        ForEach([50.0, 100, 250, 500], id: \.self) { Text("\(Int($0)) m").tag($0) }
                    }
                    Text("Save a location only when you are at that desk. Radius is a matching boundary, not an accuracy guarantee. Manual desk selection turns automatic switching off.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
        }.padding(24)
    }
}

struct AppSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var shortcut: ListeningShortcutController
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.title.weight(.semibold))
            Form {
                Section("Listening shortcut") {
                    HStack {
                        Text(shortcut.recording ? "Press your new shortcut…" : shortcut.shortcut.display)
                            .font(.title3.monospaced().weight(.medium))
                        Spacer()
                        if shortcut.recording { Button("Cancel", action: shortcut.cancelRecording) }
                        else {
                            Button("Change Shortcut", action: shortcut.beginRecording)
                            Button("Reset to ⌘H") { shortcut.change(to: .standard) }
                        }
                    }
                    Text("Include Command, Control, or Option. Press Escape to cancel. Your shortcut works while Holo is running, even with its window closed.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = shortcut.error { Text(error).foregroundStyle(.red) }
                    if shortcut.shortcut == .standard {
                        Text("⌘H replaces the usual Hide shortcut while Holo runs.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Microphone and background") {
                    LabeledContent("Microphone", value: "Built-in MacBook microphone")
                    LabeledContent("On launch", value: "Paused")
                    LabeledContent("When the window closes", value: "Keep running in the menu bar")
                    LabeledContent("When the Mac sleeps", value: "Pause listening")
                }
                Section("Advanced") {
                    Button("Open Diagnostics") { model.section = .diagnostics }
                    Text("Microphone details, experimental sensing comparisons, diagnostic exports and debug recording remain available here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
        }.padding(24)
        .onDisappear { shortcut.cancelRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in shortcut.cancelRecording() }
    }
}
