import SwiftUI
import AppKit

// SidebarView.swift
// Left column: connected devices, then the backups in each of the two folders (newest first).

struct SidebarView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var ui: WindowState

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { ui.selection },
            set: { item in ui.pick(item) }
        )
    }

    private var ownBackups: [Backup] {
        return model.backups.filter { $0.source != "Finder" }
    }

    private var finderBackups: [Backup] {
        return model.backups.filter { $0.source == "Finder" }
    }

    var body: some View {
        List(selection: selection) {
            Section("Devices") {
                deviceRows
            }
            Section("Backups in PhoneVault Folder") {
                backupRows(ownBackups, emptyText: "No backups here yet. Select a device and click Back Up Now.")
            }
            Section("Backups in Finder's Folder") {
                if model.finderAccess == .denied {
                    FinderAccessNotice()
                } else {
                    backupRows(finderBackups, emptyText: "No backups made by Finder were found.")
                }
            }
        }
        .listStyle(.sidebar)
    }

    // The rows are built here, directly inside the List, so their tags drive the selection.

    @ViewBuilder private var deviceRows: some View {
        if model.devices.isEmpty {
            SidebarHint(text: "No device connected. Plug one in with a USB cable and unlock it.")
        } else {
            ForEach(model.devices) { device in
                DeviceRow(device: device, busy: model.busy && ui.jobDeviceID == device.id)
                    .tag(SidebarItem.device(device.id))
                    .contextMenu {
                        DeviceRowMenu(device: device)
                    }
            }
        }
    }

    @ViewBuilder private func backupRows(_ backups: [Backup], emptyText: String) -> some View {
        if backups.isEmpty {
            SidebarHint(text: emptyText)
        } else {
            ForEach(backups) { backup in
                BackupRow(backup: backup, size: model.backupSizes[backup.id])
                    .tag(SidebarItem.backup(backup.id))
                    .contextMenu {
                        BackupRowMenu(model: model, ui: ui, backup: backup)
                    }
            }
        }
    }
}

/// Quiet explanatory text shown in place of rows.
struct SidebarHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Devices

struct DeviceRowMenu: View {
    let device: Device

    var body: some View {
        Button("Copy UDID") { Look.copy(device.id) }
        if !device.serial.isEmpty {
            Button("Copy Serial Number") { Look.copy(device.serial) }
        }
    }
}

struct DeviceRow: View {
    let device: Device
    let busy: Bool

    private var subtitle: String {
        if busy { return "Working…" }
        if !device.trusted { return device.trust.explanation }
        return device.model + " · " + Look.osText(for: device)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: Look.symbol(deviceClass: device.deviceClass, model: device.model + " " + device.productType))
                .font(.title3)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            DeviceStateMark(trusted: device.trusted, busy: busy)
        }
        .padding(.vertical, 3)
    }
}

/// Connected, needs Trust, or busy. Each state has its own shape and a spoken label, not only a colour.
struct DeviceStateMark: View {
    let trusted: Bool
    let busy: Bool

    var body: some View {
        if busy {
            ProgressView()
                .controlSize(.small)
                .help("A job is running on this device")
                .accessibilityLabel(Text("Busy"))
        } else if trusted {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Connected and trusted")
                .accessibilityLabel(Text("Connected"))
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("This device has not trusted this Mac yet")
                .accessibilityLabel(Text("Needs Trust"))
        }
    }
}

// MARK: - Backups

/// Right-click menu of a backup row. The model and window state are passed in directly
/// because menu content is built outside the window's view tree.
struct BackupRowMenu: View {
    let model: Model
    let ui: WindowState
    let backup: Backup

    var body: some View {
        Button("Show in Finder") { model.reveal(backup) }
        Button("Archive") { model.archive(backup) }
            .disabled(backup.archived || model.fileActionProblem(backup) != nil)
        Divider()
        Button("Move to Trash…") { ui.confirmation = .trash(backup) }
            .disabled(model.fileActionProblem(backup) != nil)
    }
}

/// Finder's folder needs Full Disk Access; this takes the place of the rows when it is missing.
struct FinderAccessNotice: View {
    @EnvironmentObject var model: Model

    private var text: String {
        if !model.finderNote.isEmpty { return model.finderNote }
        return Model.fullDiskAccessMessage
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Hidden by macOS")
                    .lineLimit(1)
                Text("Needs Full Disk Access")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Menu {
                Button("Open Privacy Settings") { model.openFullDiskAccessSettings() }
                Button("Check Again") { model.loadBackups() }
            } label: {
                Text("Allow")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 3)
        .help(text + " In the list that opens, turn on PhoneVault, then quit and reopen it.")
    }
}

struct BackupRow: View {
    let backup: Backup
    let size: Int64?

    private var dateLine: String {
        var parts: [String] = [Look.dateText(backup.date)]
        parts.append(Look.sizeText(size))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: Look.symbol(deviceClass: "", model: backup.model))
                .font(.title3)
                .frame(width: 22)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                BackupRowTitle(backup: backup)
                Text(backup.model + " · " + Look.osText(for: backup))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(dateLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !backup.complete {
                    Label("Unfinished, cannot be restored", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

/// Device name plus small marks for "encrypted" and "archived".
struct BackupRowTitle: View {
    let backup: Backup

    var body: some View {
        HStack(spacing: 5) {
            Text(backup.name)
                .lineLimit(1)
            if backup.encrypted {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Encrypted: needs its password to be restored")
                    .accessibilityLabel(Text("Encrypted"))
            }
            if backup.archived {
                Image(systemName: "archivebox.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Archived: new backups do not replace it")
                    .accessibilityLabel(Text("Archived"))
            }
        }
    }
}
