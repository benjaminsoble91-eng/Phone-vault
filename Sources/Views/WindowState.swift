import SwiftUI
import AppKit

// WindowState.swift
// View-side state shared by the window, its sheets and the menu commands:
// what the sidebar shows, which confirmation is up, and which sheet is open.
// Nothing here talks to the tools; it only calls methods of Model.

/// One row of the sidebar.
enum SidebarItem: Hashable {
    /// A connected device, by UDID.
    case device(String)
    /// A backup on disk, by `Backup.id` (its folder path).
    case backup(String)

    /// Text form kept in UserDefaults so the window reopens on the same row.
    var storageValue: String {
        switch self {
        case .device(let id): return "device:" + id
        case .backup(let id): return "backup:" + id
        }
    }

    init?(storageValue: String) {
        if storageValue.hasPrefix("device:") {
            self = .device(String(storageValue.dropFirst(7)))
        } else if storageValue.hasPrefix("backup:") {
            self = .backup(String(storageValue.dropFirst(7)))
        } else {
            return nil
        }
    }
}

/// Which change the encryption sheet is asking about.
enum EncryptionTask: String, Identifiable {
    case turnOn
    case turnOff
    case changePassword

    var id: String { return rawValue }
}

/// An action that must be confirmed before it runs. Shown by one dialog in RootView.
enum Confirmation {
    case restart(Device)
    case shutDown(Device)
    case recovery(Device)
    case unpair(Device)
    case trash(Backup)
    /// Stopping a restore part-way.
    case stopRestore
}

final class WindowState: ObservableObject {
    /// The row shown in the detail area.
    @Published var selection: SidebarItem?
    /// The confirmation waiting for an answer, if any.
    @Published var confirmation: Confirmation?
    /// True while the restore confirmation sheet is open.
    @Published var showRestoreConfirm = false
    /// The encryption sheet that is open, if any.
    @Published var encryptionTask: EncryptionTask?
    /// UDID of the device the running (or last) job was started on. Recorded by the views
    /// when `Model.busy` turns true, because the model does not publish it.
    @Published var jobDeviceID: String?
    /// Name of that device, for the activity area.
    @Published var jobDeviceName = ""

    private static let selectionKey = "sidebarSelection"
    private let launchedAt = Date()
    /// Row saved by the previous run; honoured once, shortly after launch, when it shows up.
    private var pendingSaved: SidebarItem?
    /// The backup shown last, so an archived (renamed) backup can be found again.
    private var lastShownBackup: Backup?

    init() {
        if let saved = UserDefaults.standard.string(forKey: WindowState.selectionKey) {
            pendingSaved = SidebarItem(storageValue: saved)
        }
    }

    /// The user chose a row (or cleared the selection).
    func pick(_ item: SidebarItem?) {
        pendingSaved = nil
        if selection != item { selection = item }
        if let item = item {
            UserDefaults.standard.set(item.storageValue, forKey: WindowState.selectionKey)
        }
    }

    private func exists(_ item: SidebarItem, devices: [Device], backups: [Backup]) -> Bool {
        switch item {
        case .device(let id): return devices.contains { $0.id == id }
        case .backup(let id): return backups.contains { $0.id == id }
        }
    }

    /// Keeps the selection pointing at something that still exists.
    /// Call when the device list or the backup list changes.
    func reconcile(devices: [Device], backups: [Backup]) {
        var next = selection

        if let current = next, !exists(current, devices: devices, backups: backups) {
            next = nil
            // An archived backup keeps its device and date but moves to a new folder: follow it.
            if case .backup = current, let old = lastShownBackup, old.date != nil {
                let moved = backups.first { $0.udid == old.udid && $0.root == old.root && $0.date == old.date }
                if let moved = moved { next = .backup(moved.id) }
            }
        }

        if let wanted = pendingSaved {
            if Date().timeIntervalSince(launchedAt) > 20 {
                pendingSaved = nil
            } else if exists(wanted, devices: devices, backups: backups) {
                next = wanted
                pendingSaved = nil
            }
        }

        if next == nil, let first = devices.first {
            next = .device(first.id)
        }

        if next != selection { selection = next }

        if case .some(.backup(let id)) = next {
            lastShownBackup = backups.first { $0.id == id }
        }
    }

    // MARK: Requests shared by buttons, the toolbar and the menu bar

    /// Re-reads devices, backups and free space.
    func refreshAll(_ model: Model) {
        model.checkTools()
        model.refreshDevices(forceDetails: true)
        model.loadBackups()
        model.refreshDestinationInfo()
    }

    /// Starts a backup of the model's selected device, or shows that device's page when something is in the way
    /// (the page explains what).
    func requestBackup(_ model: Model) {
        if model.backupProblem() == nil {
            model.startBackup()
        } else if let id = model.selectedDevice {
            pick(.device(id))
        }
    }

    /// Opens the restore confirmation, or shows the page that explains why a restore cannot start.
    func requestRestore(_ model: Model) {
        if model.restoreProblem() == nil {
            showRestoreConfirm = true
        } else if case .some(.backup) = selection {
            // Already on a backup page, which shows the reason.
        } else if let id = model.selectedDevice {
            pick(.device(id))
        }
    }

    /// Stops the running job; a restore is only stopped after a confirmation.
    func requestStop(_ model: Model) {
        guard model.busy, !model.cancelling else { return }
        if model.operation == .restore {
            confirmation = .stopRestore
        } else {
            model.cancel()
        }
    }
}

// MARK: - Wording and execution of confirmations

extension Confirmation {
    var title: String {
        switch self {
        case .restart(let device): return "Restart “\(device.name)”?"
        case .shutDown(let device): return "Shut down “\(device.name)”?"
        case .recovery(let device): return "Put “\(device.name)” into recovery mode?"
        case .unpair(let device): return "Unpair “\(device.name)” from this Mac?"
        case .trash(let backup): return "Move the backup of “\(backup.name)” to the Trash?"
        case .stopRestore: return "Stop the restore?"
        }
    }

    func message(_ model: Model) -> String {
        switch self {
        case .restart(let device):
            let noun = Look.noun(for: device)
            return "The \(noun) turns off and on again. Unsaved work in open apps may be lost. It shows up here again once it has started and you have unlocked it."
        case .shutDown(let device):
            let noun = Look.noun(for: device)
            return "The \(noun) powers off and disappears from PhoneVault. It stays off until you turn it on with its button."
        case .recovery(let device):
            let noun = Look.noun(for: device)
            var text = "The \(noun) restarts to a screen showing a cable and cannot be used until it leaves recovery mode. It also disappears from the device list while it is there. This step does not erase anything."
            if model.toolAvailable("irecovery") {
                text += " To bring it back, choose Device > Exit Recovery Mode."
            } else {
                text += " PhoneVault cannot bring it back on this Mac because the irecovery tool is not installed; you would have to force-restart the \(noun) with its buttons."
            }
            return text
        case .unpair(let device):
            let noun = Look.noun(for: device)
            return "This Mac forgets the \(noun) and can no longer read it, back it up or restore it. To use it again, plug it in, unlock it and tap Trust. Backups already on this Mac are kept."
        case .trash(let backup):
            var what = "The backup"
            if let date = backup.date { what += " from " + Format.date(date) }
            if let size = model.backupSizes[backup.id] { what += " (" + Format.bytes(size) + ")" }
            return what + " is moved to the Trash. You can take it back out until the Trash is emptied; after that it cannot be recovered."
        case .stopRestore:
            return "Stopping now can leave the device with only part of its data restored. You would have to run the restore again from the start."
        }
    }

    var confirmLabel: String {
        switch self {
        case .restart: return "Restart"
        case .shutDown: return "Shut Down"
        case .recovery: return "Enter Recovery Mode"
        case .unpair: return "Unpair"
        case .trash: return "Move to Trash"
        case .stopRestore: return "Stop Restore"
        }
    }

    var keepLabel: String {
        switch self {
        case .stopRestore: return "Keep Restoring"
        default: return "Cancel"
        }
    }

    func perform(_ model: Model) {
        switch self {
        case .restart(let device): model.restart(device)
        case .shutDown(let device): model.shutDown(device)
        case .recovery(let device): model.enterRecovery(device)
        case .unpair(let device): model.unpair(device)
        case .trash(let backup): model.trash(backup)
        case .stopRestore: model.cancel()
        }
    }
}
