import SwiftUI
import AppKit

// DeviceDetailView.swift
// The page for one connected device: header with identifiers, battery / storage / Find My tiles,
// then the Back Up card and the Restore card. A device that has not trusted this Mac gets
// instructions instead of the cards.

struct DeviceDetailView: View {
    @EnvironmentObject var model: Model
    let device: Device

    private var subtitle: String {
        if !device.trusted { return "Waiting for Trust" }
        return device.model + " · " + Look.osText(for: device)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DeviceHeader(device: device)
                if device.trusted {
                    DeviceMeters(device: device, details: model.details[device.id])
                    BackupCard(device: device)
                    RestorePanel(context: .ontoDevice(device))
                } else {
                    TrustCard(device: device)
                }
            }
            .padding(20)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(device.name)
        .navigationSubtitle(subtitle)
    }
}

// MARK: - Header

struct DeviceHeader: View {
    let device: Device

    private var summary: String {
        if !device.trusted { return device.trust.explanation }
        var text = device.model + " · " + Look.osText(for: device)
        if !device.build.isEmpty { text += " (" + device.build + ")" }
        return text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            IconTile(systemImage: Look.symbol(deviceClass: device.deviceClass, model: device.model + " " + device.productType),
                     tint: device.trusted ? .accentColor : .orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(device.name)
                    .font(.title.weight(.semibold))
                    .textSelection(.enabled)
                Text(summary)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DeviceIdentifiers(device: device)
                    .padding(.top, 4)
            }
            Spacer(minLength: 12)
            DeviceActionsMenu(device: device)
        }
    }
}

struct DeviceIdentifiers: View {
    let device: Device

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !device.serial.isEmpty {
                IdentifierLine(label: "Serial number", value: device.serial, what: "serial number")
            }
            IdentifierLine(label: "UDID", value: device.id, what: "UDID")
            if !device.productType.isEmpty {
                IdentifierLine(label: "Model identifier", value: device.productType, what: "model identifier")
            }
        }
    }
}

struct IdentifierLine: View {
    let label: String
    let value: String
    let what: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            CopyableValue(text: value, what: what)
        }
    }
}

// MARK: - Actions menu

/// Pairing, restart, shut down and recovery mode. Everything that changes the device asks first
/// (the dialog lives in RootView).
struct DeviceActionsMenu: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var ui: WindowState
    let device: Device

    private func blocked(_ tool: String) -> Bool {
        return model.deviceActionProblem(device, tool: tool) != nil
    }

    private var missingNote: String {
        let wanted = ["idevicepair", "idevicediagnostics", "ideviceenterrecovery"]
        let missing = wanted.filter { !model.toolAvailable($0) }
        if missing.isEmpty { return "" }
        return "Some actions are missing because these tools are not installed: " + missing.joined(separator: ", ")
    }

    var body: some View {
        Menu {
            if model.toolAvailable("idevicediagnostics") {
                Button("Restart…") { ui.confirmation = .restart(device) }
                    .disabled(blocked("idevicediagnostics"))
                Button("Shut Down…") { ui.confirmation = .shutDown(device) }
                    .disabled(blocked("idevicediagnostics"))
            }
            if model.toolAvailable("ideviceenterrecovery") {
                Button("Enter Recovery Mode…") { ui.confirmation = .recovery(device) }
                    .disabled(blocked("ideviceenterrecovery"))
            }
            if model.toolAvailable("idevicepair") {
                Divider()
                Button("Ask the Device to Trust This Mac") { model.pair(device) }
                    .disabled(blocked("idevicepair"))
                Button("Unpair from This Mac…") { ui.confirmation = .unpair(device) }
                    .disabled(blocked("idevicepair"))
            }
            Divider()
            Button("Copy UDID") { Look.copy(device.id) }
            if !missingNote.isEmpty {
                Divider()
                Text(missingNote)
            }
        } label: {
            Label("Device Actions", systemImage: "ellipsis.circle")
        }
        .fixedSize()
        .help("Restart, shut down, recovery mode and pairing")
    }
}

// MARK: - Tiles

struct DeviceMeters: View {
    let device: Device
    let details: DeviceDetails?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BatteryTile(details: details)
            StorageTile(details: details)
            FindMyTile(device: device, details: details)
        }
    }
}

struct BatteryTile: View {
    let details: DeviceDetails?

    private var symbol: String {
        guard let percent = details?.batteryPercent else { return "battery.0" }
        if details?.charging == true { return "battery.100.bolt" }
        if percent >= 88 { return "battery.100" }
        if percent >= 63 { return "battery.75" }
        if percent >= 38 { return "battery.50" }
        if percent >= 13 { return "battery.25" }
        return "battery.0"
    }

    private var value: String {
        guard let percent = details?.batteryPercent else { return "Not reported" }
        return "\(percent)%"
    }

    private var caption: String {
        guard details?.batteryPercent != nil else {
            return details == nil ? "Reading the device…" : "The device did not report its battery level."
        }
        if details?.charging == true { return "Charging" }
        if details?.charging == false { return "Not charging" }
        return "Charge level"
    }

    private var fraction: Double? {
        guard let percent = details?.batteryPercent else { return nil }
        return Double(percent) / 100
    }

    var body: some View {
        MeterTile(title: "Battery", systemImage: symbol, value: value, caption: caption, fraction: fraction, tint: tint)
    }

    private var tint: Color {
        guard let percent = details?.batteryPercent else { return .accentColor }
        if details?.charging == true || percent >= 40 { return .green }
        if percent >= 20 { return .orange }
        return .red
    }
}

struct StorageTile: View {
    let details: DeviceDetails?

    private var value: String {
        guard let used = details?.storageUsed else { return "Not reported" }
        return Format.bytes(used) + " used"
    }

    private var caption: String {
        guard let total = details?.storageTotal, let free = details?.storageFree else {
            return details == nil ? "Reading the device…" : "The device did not report its storage."
        }
        return Format.bytes(free) + " free of " + Format.bytes(total)
    }

    private var fraction: Double? {
        guard let total = details?.storageTotal, let used = details?.storageUsed, total > 0 else { return nil }
        return Double(used) / Double(total)
    }

    var body: some View {
        MeterTile(title: "Storage", systemImage: "internaldrive", value: value, caption: caption, fraction: fraction, tint: tint)
    }

    private var tint: Color {
        guard let fraction = fraction else { return .accentColor }
        if fraction >= 0.95 { return .red }
        if fraction >= 0.85 { return .orange }
        return .accentColor
    }
}

struct FindMyTile: View {
    let device: Device
    let details: DeviceDetails?

    private var value: String {
        guard let on = details?.findMy else { return "Unknown" }
        return on ? "On" : "Off"
    }

    private var caption: String {
        guard let on = details?.findMy else {
            return details == nil ? "Reading the device…" : "Could not be checked. It has to be off before a restore."
        }
        if on { return "Has to be turned off on the \(Look.noun(for: device)) before a backup can be restored onto it." }
        return "A backup can be restored onto this \(Look.noun(for: device))."
    }

    var body: some View {
        MeterTile(title: "Find My", systemImage: "location", value: value, caption: caption, fraction: nil)
    }
}

// MARK: - Not trusted yet

struct TrustCard: View {
    @EnvironmentObject var model: Model
    let device: Device

    private var askProblem: String? {
        if !model.toolAvailable("idevicepair") {
            return "PhoneVault cannot ask again on its own because the idevicepair tool is not installed. Unplug the device and plug it back in instead."
        }
        return model.deviceActionProblem(device, tool: "idevicepair")
    }

    /// A device that declined, or was unpaired here, is not asked again until the user says so.
    private var waitingNote: String {
        if device.trust == .denied || device.trust == .notPaired {
            return "PhoneVault does not ask this device again by itself. Click Ask Again, or unplug it and plug it back in, to get the Trust question on its screen."
        }
        return "PhoneVault checks every few seconds; this page changes by itself once the device trusts this Mac."
    }

    var body: some View {
        Card("This device has not trusted this Mac yet", systemImage: "hand.raised") {
            Notice(.warning, device.trust.explanation)
            VStack(alignment: .leading, spacing: 8) {
                StepLine(number: 1, text: "Unlock the device with its passcode and leave it on the Home Screen.")
                StepLine(number: 2, text: "When it asks “Trust This Computer?”, tap Trust and enter the passcode.")
                StepLine(number: 3, text: "Nothing on the screen? Click Ask Again, or unplug the cable and plug it back in.")
            }
            HStack(spacing: 10) {
                Button("Ask Again") { model.pair(device) }
                    .disabled(askProblem != nil)
                Button("Refresh") { model.refreshDevices(forceDetails: true) }
            }
            if let problem = askProblem {
                Notice(.info, problem)
            }
            Text(waitingNote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "1  Do this" line used by the instructions.
struct StepLine: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number).")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
