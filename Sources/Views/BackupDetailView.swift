import SwiftUI
import AppKit

// BackupDetailView.swift
// The page for one backup on disk: what it is, where it lives, file actions,
// and the Restore card for putting it onto a connected device.

struct BackupDetailView: View {
    @EnvironmentObject var model: Model
    let backup: Backup

    private var subtitle: String {
        return "Backup · " + Look.dateText(backup.date)
    }

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: 16) {
                BackupHeader(backup: backup)
                if !backup.complete {
                    Notice(.warning, "This backup was never finished, so it cannot be restored. Back up the device again; after that you can move this one to the Trash.")
                }
                BackupFactsCard(backup: backup)
                BackupFileActionsCard(backup: backup)
                RestorePanel(context: .fromBackup(backup))
            }
            .padding(20)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(backup.name)
        .navigationSubtitle(subtitle)
    }
}

// MARK: - Header

struct BackupHeader: View {
    let backup: Backup

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            IconTile(systemImage: "clock.arrow.circlepath", tint: .indigo)
            VStack(alignment: .leading, spacing: 6) {
                Text("Backup of " + backup.name)
                    .font(.title.weight(.semibold))
                    .textSelection(.enabled)
                Text(backup.model + " · " + Look.osText(for: backup))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                BackupPills(backup: backup)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }
}

struct BackupPills: View {
    let backup: Backup

    var body: some View {
        HStack(spacing: 6) {
            if backup.encrypted {
                Pill(text: "Encrypted", systemImage: "lock.fill")
            } else {
                Pill(text: "Not encrypted", systemImage: "lock.open")
            }
            if backup.archived {
                Pill(text: "Archived", systemImage: "archivebox")
            }
            if !backup.complete {
                Pill(text: "Unfinished", systemImage: "exclamationmark.triangle")
            }
        }
    }
}

// MARK: - Facts

struct BackupFactsCard: View {
    @EnvironmentObject var model: Model
    let backup: Backup

    private var dateText: String {
        guard let date = backup.date else { return "Date unknown" }
        return Format.date(date) + " (" + Look.relative(date) + ")"
    }

    private var encryptionText: String {
        if backup.encrypted { return "Encrypted. Its password is needed to restore it." }
        return "Not encrypted. It does not contain saved passwords, Wi-Fi settings, Health data or call history."
    }

    private var keptText: String {
        if backup.archived { return "Archived. New backups of this device do not change it." }
        return "Current. The next backup of this device into the same folder updates it."
    }

    var body: some View {
        Card("About This Backup", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow("Backed up") { Text(dateText) }
                InfoRow("Size on this Mac") { Text(Look.sizeText(model.backupSizes[backup.id])).monospacedDigit() }
                InfoRow("Device") { Text(backup.name + " · " + backup.model + " · " + Look.osText(for: backup)) }
                InfoRow("Encryption") { Text(encryptionText).fixedSize(horizontal: false, vertical: true) }
                InfoRow("Status") { Text(keptText).fixedSize(horizontal: false, vertical: true) }
                InfoRow("Kept in") { Text(Look.folderName(for: backup)) }
                InfoRow("Folder") { CopyableValue(text: Look.tildePath(backup.path), what: "folder path") }
                if !backup.serial.isEmpty {
                    InfoRow("Serial number") { CopyableValue(text: backup.serial, what: "serial number") }
                }
                InfoRow("UDID") { CopyableValue(text: backup.udid, what: "UDID") }
            }
        }
    }
}

// MARK: - File actions

struct BackupFileActionsCard: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var ui: WindowState
    let backup: Backup

    private var problem: String? {
        return model.fileActionProblem(backup)
    }

    var body: some View {
        Card("Manage", systemImage: "folder") {
            HStack(spacing: 10) {
                Button {
                    model.reveal(backup)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                Button {
                    model.archive(backup)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .disabled(backup.archived || problem != nil)
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    ui.confirmation = .trash(backup)
                } label: {
                    Label("Move to Trash…", systemImage: "trash")
                }
                .disabled(problem != nil)
            }
            Text("Archive keeps this backup exactly as it is: the next backup of the device starts a new one instead of updating this one. An archived backup can still be restored.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let problem = problem {
                Notice(.info, problem)
            }
        }
    }
}
