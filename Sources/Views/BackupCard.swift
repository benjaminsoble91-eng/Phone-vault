import SwiftUI
import AppKit

// BackupCard.swift
// The "Back Up" card on a device page: where the backup goes, the last backup,
// backup encryption with its Manage menu, and the Back Up Now button.

struct BackupCard: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var ui: WindowState
    let device: Device

    var body: some View {
        Card("Back Up", systemImage: "arrow.down.doc") {
            LastBackupLine(device: device)
            Divider()
            DestinationRows()
            Divider()
            EncryptionRow(device: device)
            Divider()
            BackupStartRow(device: device)
        }
    }
}

// MARK: - Last backup

struct LastBackupLine: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var ui: WindowState
    let device: Device

    /// Newest backup of this device (the model keeps the list newest first).
    private var latest: Backup? {
        return model.backups(for: device.id).first
    }

    private func describe(_ backup: Backup) -> String {
        var text = Look.dateText(backup.date)
        if let date = backup.date { text += " (" + Look.relative(date) + ")" }
        text += " · " + Look.sizeText(model.backupSizes[backup.id])
        text += " · " + Look.folderName(for: backup)
        return text
    }

    var body: some View {
        InfoRow("Last backup") {
            if let backup = latest {
                Text(describe(backup))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Show") { ui.pick(.backup(backup.id)) }
                    .buttonStyle(.link)
                    .help("Open this backup's page")
            } else {
                Text("This \(Look.noun(for: device)) has not been backed up to this Mac yet.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Destination

struct DestinationRows: View {
    @EnvironmentObject var model: Model

    private var freeText: String {
        guard let free = model.destinationFree else { return "" }
        return Format.bytes(free) + " free on this Mac"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InfoRow("Save to") {
                Picker("Save to", selection: $model.destination) {
                    ForEach(BackupDestination.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                Button("Show Folder") { model.revealBackupsFolder() }
            }
            InfoRow("") {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Look.tildePath(model.destinationRoot))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    if !freeText.isEmpty {
                        Text(freeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let problem = model.destinationProblem {
                InfoRow("") {
                    VStack(alignment: .leading, spacing: 6) {
                        Notice(.warning, problem)
                        Button("Open Privacy Settings") { model.openFullDiskAccessSettings() }
                    }
                }
            }
        }
    }
}

// MARK: - Encryption

struct EncryptionRow: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var ui: WindowState
    let device: Device

    private var state: Bool? {
        return model.details[device.id]?.backupEncryption
    }

    private var symbol: String {
        if state == true { return "lock.fill" }
        if state == false { return "lock.open" }
        return "lock"
    }

    private var headline: String {
        if state == true { return "On. Backups of this \(Look.noun(for: device)) are protected with a password." }
        if state == false { return "Off. Backups of this \(Look.noun(for: device)) are not protected." }
        return "Not known yet."
    }

    private var explanation: String {
        if state == true {
            return "You need that password to restore one of these backups. PhoneVault does not store it and cannot recover it."
        }
        if state == false {
            return "Without encryption a backup leaves out saved passwords, Wi-Fi settings, Health data and call history."
        }
        return "PhoneVault is still reading this setting from the device."
    }

    private func open(_ task: EncryptionTask) {
        model.selectedDevice = device.id
        ui.encryptionTask = task
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InfoRow("Encryption") {
                Label(headline, systemImage: symbol)
                    .fixedSize(horizontal: false, vertical: true)
            }
            InfoRow("") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    manageMenu
                    if let problem = model.encryptionProblem(), !model.busy {
                        Notice(.info, problem)
                    }
                }
            }
        }
    }

    private var manageMenu: some View {
        Menu("Manage Encryption") {
            if state != true {
                Button("Turn On Encryption…") { open(.turnOn) }
            }
            if state != false {
                Button("Change Password…") { open(.changePassword) }
                Button("Turn Off Encryption…") { open(.turnOff) }
            }
        }
        .fixedSize()
        .disabled(model.encryptionProblem() != nil)
    }
}

// MARK: - Start

struct BackupStartRow: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var ui: WindowState
    let device: Device

    /// True when the next backup will update a backup that is already in the chosen folder.
    private var willUpdateExisting: Bool {
        let root = model.destinationRoot
        return model.backups(for: device.id).contains { !$0.archived && $0.root == root }
    }

    private func start() {
        model.selectedDevice = device.id
        model.startBackup()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $model.forceFullBackup) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Copy everything again")
                    Text("Slower, but does not rely on what an earlier backup already holds. Turn off to copy only what changed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if willUpdateExisting {
                Notice(.info, "This updates the existing backup in the chosen folder. To keep that one as it is, open it and choose Archive first.")
            }
            if let warning = model.backupWarning() {
                Notice(.warning, warning)
            }
            HStack(alignment: .center, spacing: 12) {
                Button {
                    start()
                } label: {
                    Label("Back Up Now", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.backupProblem() != nil)
                Text("Keep the \(Look.noun(for: device)) plugged in and unlocked until the backup is finished.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem = model.backupProblem(), !model.busy {
                Notice(.info, problem)
            }
        }
    }
}
