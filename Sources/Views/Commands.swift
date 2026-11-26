import SwiftUI
import AppKit

// Commands.swift
// The menu bar: a Device menu and a Backups menu with keyboard shortcuts.
// Destructive items only open the same confirmations the buttons in the window use.

struct PhoneVaultCommands: Commands {
    @ObservedObject var model: Model
    @ObservedObject var ui: WindowState

    var body: some Commands {
        // One window only: its sheets and confirmations belong to a single shared WindowState.
        CommandGroup(replacing: .newItem) { }
        SidebarCommands()
        CommandGroup(after: .sidebar) {
            AppearanceMenuItems()
        }
        CommandMenu("Device") {
            DeviceMenuItems(model: model, ui: ui)
        }
        CommandMenu("Backups") {
            BackupMenuItems(model: model, ui: ui)
        }
    }
}

struct DeviceMenuItems: View {
    @ObservedObject var model: Model
    @ObservedObject var ui: WindowState

    private var backUpTitle: String {
        if let device = model.chosenDevice { return "Back Up “\(device.name)” Now" }
        return "Back Up Now"
    }

    private var restoreTitle: String {
        if let device = model.chosenDevice { return "Restore “\(device.name)”…" }
        return "Restore…"
    }

    var body: some View {
        Button("Refresh") { ui.refreshAll(model) }
            .keyboardShortcut("r", modifiers: .command)

        Divider()

        Button(backUpTitle) { ui.requestBackup(model) }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(model.chosenDevice == nil || !model.canStart)

        Button(restoreTitle) { ui.requestRestore(model) }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model.chosenDevice == nil || !model.canStart)

        Button("Stop Current Job") { ui.requestStop(model) }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!model.busy || model.cancelling)

        Divider()

        DeviceMenuActions(model: model, ui: ui)
    }
}

/// Restart, shut down, recovery mode and pairing for the selected device.
struct DeviceMenuActions: View {
    @ObservedObject var model: Model
    @ObservedObject var ui: WindowState

    private func blocked(_ tool: String) -> Bool {
        guard let device = model.chosenDevice else { return true }
        return model.deviceActionProblem(device, tool: tool) != nil
    }

    var body: some View {
        Button("Restart…") {
            if let device = model.chosenDevice { ui.confirmation = .restart(device) }
        }
        .disabled(blocked("idevicediagnostics"))

        Button("Shut Down…") {
            if let device = model.chosenDevice { ui.confirmation = .shutDown(device) }
        }
        .disabled(blocked("idevicediagnostics"))

        Button("Enter Recovery Mode…") {
            if let device = model.chosenDevice { ui.confirmation = .recovery(device) }
        }
        .disabled(blocked("ideviceenterrecovery"))

        Button("Exit Recovery Mode") { model.exitRecovery() }
            .disabled(!model.canStart)

        Divider()

        Button("Ask the Device to Trust This Mac") {
            if let device = model.chosenDevice { model.pair(device) }
        }
        .disabled(blocked("idevicepair"))

        Button("Unpair from This Mac…") {
            if let device = model.chosenDevice { ui.confirmation = .unpair(device) }
        }
        .disabled(blocked("idevicepair"))
    }
}

struct BackupMenuItems: View {
    @ObservedObject var model: Model
    @ObservedObject var ui: WindowState

    /// The backup shown in the window, if a backup page is open.
    private var shownBackup: Backup? {
        guard case .some(.backup(let id)) = ui.selection else { return nil }
        return model.backups.first { $0.id == id }
    }

    private func blocked(_ backup: Backup?) -> Bool {
        guard let backup = backup else { return true }
        return model.fileActionProblem(backup) != nil
    }

    var body: some View {
        Button("Show Backups Folder in Finder") { model.revealBackupsFolder() }
            .keyboardShortcut("o", modifiers: [.command, .shift])

        Button("Look for Backups Again") { model.loadBackups() }

        Divider()

        Button("Show Selected Backup in Finder") {
            if let backup = shownBackup { model.reveal(backup) }
        }
        .disabled(shownBackup == nil)

        Button("Archive Selected Backup") {
            if let backup = shownBackup { model.archive(backup) }
        }
        .disabled(blocked(shownBackup) || (shownBackup?.archived ?? true))

        Button("Move Selected Backup to Trash…") {
            if let backup = shownBackup { ui.confirmation = .trash(backup) }
        }
        .keyboardShortcut(.delete, modifiers: .command)
        .disabled(blocked(shownBackup))
    }
}
