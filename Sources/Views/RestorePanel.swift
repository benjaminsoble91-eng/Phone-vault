import SwiftUI
import AppKit

// RestorePanel.swift
// The "Restore" card. Used on a device page (pick the backup) and on a backup page (pick the device).
// It shows the model's pre-check message inline and only then lets the user open the confirmation sheet,
// which is the single place a restore can be started from.

/// Which side of the restore is fixed by the page the card is on.
enum RestoreContext {
    /// On a device page: the device is given, the user picks the backup.
    case ontoDevice(Device)
    /// On a backup page: the backup is given, the user picks the device.
    case fromBackup(Backup)
}

struct RestorePanel: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var ui: WindowState
    let context: RestoreContext

    private var title: String {
        switch context {
        case .ontoDevice: return "Restore from a Backup"
        case .fromBackup: return "Restore onto a Device"
        }
    }

    var body: some View {
        Card(title, systemImage: "clock.arrow.circlepath") {
            chooser
            if let backup = model.chosenBackup, backup.encrypted {
                RestorePasswordRow()
            }
            RestoreOptions()
            Divider()
            RestoreStartRow()
        }
        .onAppear { claim() }
    }

    @ViewBuilder private var chooser: some View {
        switch context {
        case .ontoDevice(let device):
            RestoreBackupChooser(device: device)
        case .fromBackup(let backup):
            RestoreDeviceChooser(backup: backup)
        }
    }

    /// Makes sure the model is pointing at the device or backup this page is about.
    private func claim() {
        switch context {
        case .ontoDevice(let device):
            if model.selectedDevice != device.id { model.selectedDevice = device.id }
        case .fromBackup(let backup):
            if model.selectedBackup != backup.id { model.selectedBackup = backup.id }
        }
    }
}

// MARK: - Choosing the backup (device page)

struct RestoreBackupChooser: View {
    @EnvironmentObject var model: Model
    let device: Device

    private var own: [Backup] {
        return model.backups(for: device.id)
    }

    private var others: [Backup] {
        let wanted = device.id.lowercased()
        return model.backups.filter { $0.udid.lowercased() != wanted }
    }

    private func label(_ backup: Backup) -> String {
        var text = backup.name + ", " + Look.dateText(backup.date) + ", " + Look.osText(for: backup)
        if backup.archived { text += ", archived" }
        if !backup.complete { text += ", unfinished" }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.backups.isEmpty {
                Notice(.info, "There are no backups on this Mac yet. Make one with Back Up Now.")
            } else {
                InfoRow("Backup") {
                    Picker("Backup", selection: $model.selectedBackup) {
                        Text("Choose a backup").tag(String?.none)
                        if !own.isEmpty {
                            Section("From this \(Look.noun(for: device))") {
                                ForEach(own) { backup in
                                    Text(label(backup)).tag(String?.some(backup.id))
                                }
                            }
                        }
                        if !others.isEmpty {
                            Section("From other devices") {
                                ForEach(others) { backup in
                                    Text(label(backup)).tag(String?.some(backup.id))
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 440)
                }
                if let backup = model.chosenBackup {
                    InfoRow("") {
                        ChosenBackupSummary(backup: backup, device: device)
                    }
                }
            }
        }
    }
}

/// Two quiet lines under the picker describing the chosen backup.
struct ChosenBackupSummary: View {
    @EnvironmentObject var model: Model
    let backup: Backup
    let device: Device

    private var facts: String {
        var parts: [String] = [backup.model, Look.osText(for: backup)]
        parts.append(Look.sizeText(model.backupSizes[backup.id]))
        parts.append(Look.folderName(for: backup))
        return parts.joined(separator: " · ")
    }

    private var fromOtherDevice: Bool {
        return backup.udid.lowercased() != device.id.lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(facts)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if backup.encrypted {
                    Pill(text: "Encrypted", systemImage: "lock.fill")
                }
                if backup.archived {
                    Pill(text: "Archived", systemImage: "archivebox")
                }
                if fromOtherDevice {
                    Pill(text: "From a different device", systemImage: "arrow.left.arrow.right")
                }
            }
        }
    }
}

// MARK: - Choosing the device (backup page)

struct RestoreDeviceChooser: View {
    @EnvironmentObject var model: Model
    let backup: Backup

    private func label(_ device: Device) -> String {
        if !device.trusted { return device.name }
        var text = device.name + ", " + device.model + ", " + Look.osText(for: device)
        if device.id.lowercased() == backup.udid.lowercased() { text += " (the device this backup came from)" }
        return text
    }

    var body: some View {
        if model.devices.isEmpty {
            Notice(.info, "Connect the device you want to restore onto with a USB cable, unlock it and tap Trust.")
        } else {
            InfoRow("Restore onto") {
                Picker("Restore onto", selection: $model.selectedDevice) {
                    Text("Choose a device").tag(String?.none)
                    ForEach(model.devices) { device in
                        Text(label(device)).tag(String?.some(device.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 440)
            }
        }
    }
}

// MARK: - Password

struct RestorePasswordRow: View {
    @EnvironmentObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InfoRow("Password") {
                SecureField("Password of this backup", text: $model.password)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }
            InfoRow("") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This backup is encrypted. Enter the password that was set when encryption was turned on. It is used for this restore only and is not saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !model.passwordNote.isEmpty {
                        Notice(.warning, model.passwordNote)
                    }
                }
            }
        }
    }
}

// MARK: - Options

struct RestoreOptions: View {
    @EnvironmentObject var model: Model
    @AppStorage("showRestoreOptions") private var expanded = false

    var body: some View {
        DisclosureGroup("Options", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                OptionToggle(isOn: $model.restoreSystemFiles,
                             title: "Restore system files",
                             detail: "Includes the system-level data stored in the backup. Recommended.")
                OptionToggle(isOn: $model.restoreSettings,
                             title: "Restore settings",
                             detail: "Replaces the device's settings with the ones in the backup.")
                OptionToggle(isOn: $model.restoreReboot,
                             title: "Restart the device when the restore is done",
                             detail: "The restored data is only picked up after a restart.")
                OptionToggle(isOn: $model.restoreSkipApps,
                             title: "Do not reinstall apps",
                             detail: "Normally the device downloads its apps again after the restore.")
                OptionToggle(isOn: $model.restoreRemoveItems,
                             title: "Remove items that are not in the backup",
                             detail: "Deletes content on the device that the backup does not contain.")
                OptionToggle(isOn: $model.restoreCopyFirst,
                             title: "Work from a copy of the backup",
                             detail: "Copies the backup folder first, so this Mac needs room for it a second time.")
            }
            .padding(.top, 8)
            .padding(.leading, 4)
        }
    }
}

struct OptionToggle: View {
    @Binding var isOn: Bool
    let title: String
    let detail: String

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Pre-check and start

struct RestoreStartRow: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var ui: WindowState

    private var readyText: String {
        guard let device = model.chosenDevice, let backup = model.chosenBackup else { return "" }
        return "Ready to put the backup of “\(backup.name)” from \(Look.dateText(backup.date)) onto “\(device.name)”. You will be asked to confirm."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let problem = model.restoreProblem() {
                if !model.busy {
                    Notice(.warning, problem)
                }
            } else {
                Notice(.success, readyText)
            }
            Button {
                ui.requestRestore(model)
            } label: {
                Label("Restore…", systemImage: "clock.arrow.circlepath")
            }
            .controlSize(.large)
            .disabled(model.restoreProblem() != nil)
        }
    }
}

// MARK: - Confirmation sheet

/// The last step before a restore: what goes where, every warning from the model,
/// and a tick box that has to be set before the Restore button works.
struct RestoreConfirmSheet: View {
    @EnvironmentObject var model: Model
    @Environment(\.dismiss) private var dismiss
    @State private var understood = false
    /// What the sheet was opened for. If the model's selection moves away (device unplugged,
    /// backup removed), the sheet refuses to continue instead of restoring something else.
    @State private var openedDevice: String?
    @State private var openedBackup: String?

    private var deviceName: String {
        return model.chosenDevice?.name ?? "the device"
    }

    private var changedProblem: String? {
        if let id = openedDevice, model.selectedDevice != id {
            return "The device this was opened for is no longer connected or selected. Close this and start again."
        }
        if let id = openedBackup, model.selectedBackup != id {
            return "The backup this was opened for is no longer selected. Close this and start again."
        }
        return nil
    }

    private var problem: String? {
        return changedProblem ?? model.restoreProblem()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RestoreConfirmHeader(deviceName: deviceName)
            RestoreConfirmSummary()
            RestoreWarningList(warnings: model.restoreWarnings())
            if let problem = problem {
                Notice(.problem, problem)
            }
            Toggle(isOn: $understood) {
                Text("I understand that this replaces data on “\(deviceName)” and cannot be undone.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Restore", role: .destructive) { confirm() }
                    .disabled(!understood || problem != nil)
            }
        }
        .padding(22)
        .frame(width: 540)
        .onAppear {
            if openedDevice == nil { openedDevice = model.selectedDevice }
            if openedBackup == nil { openedBackup = model.selectedBackup }
        }
    }

    private func confirm() {
        guard understood, problem == nil else { return }
        model.startRestore()
        dismiss()
    }
}

struct RestoreConfirmHeader: View {
    let deviceName: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.orange)
                .accessibilityLabel(Text("Warning"))
            VStack(alignment: .leading, spacing: 4) {
                Text("Restore “\(deviceName)” from this backup?")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Read the points below before you continue.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RestoreConfirmSummary: View {
    @EnvironmentObject var model: Model

    private var backupText: String {
        guard let backup = model.chosenBackup else { return "No backup chosen" }
        var parts: [String] = [backup.name, backup.model, Look.osText(for: backup), Look.dateText(backup.date)]
        if let size = model.backupSizes[backup.id] { parts.append(Format.bytes(size)) }
        if backup.encrypted { parts.append("encrypted") }
        return parts.joined(separator: " · ")
    }

    private var deviceText: String {
        guard let device = model.chosenDevice else { return "No device chosen" }
        return [device.name, device.model, Look.osText(for: device)].joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InfoRow("Backup") {
                Text(backupText).fixedSize(horizontal: false, vertical: true)
            }
            InfoRow("Goes onto") {
                Text(deviceText).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardBackground())
    }
}

struct RestoreWarningList: View {
    let warnings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(warnings.indices, id: \.self) { index in
                Notice(.warning, warnings[index])
            }
        }
    }
}
