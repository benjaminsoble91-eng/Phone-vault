import SwiftUI
import AppKit

// RootView.swift
// The window: install screen when the tools are missing, otherwise sidebar + detail.
// Also owns the one confirmation dialog, the sheets, and the glue between the sidebar
// selection (WindowState) and the model's selectedDevice / selectedBackup.

struct RootView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var ui: WindowState

    var body: some View {
        content
            .modifier(SelectionSync())
            .modifier(Dialogs())
    }

    @ViewBuilder private var content: some View {
        if model.toolsMissing {
            ToolsMissingView()
        } else {
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 380)
            } detail: {
                DetailView()
            }
        }
    }
}

/// Keeps WindowState.selection and the model's two selections in step.
struct SelectionSync: ViewModifier {
    @EnvironmentObject var model: Model
    @EnvironmentObject var ui: WindowState

    func body(content: Content) -> some View {
        content
            .onAppear {
                ui.reconcile(devices: model.devices, backups: model.backups)
                push(ui.selection)
            }
            .onChange(of: model.devices) { devices in
                ui.reconcile(devices: devices, backups: model.backups)
            }
            .onChange(of: model.backups) { backups in
                ui.reconcile(devices: model.devices, backups: backups)
            }
            .onChange(of: ui.selection) { item in
                push(item)
            }
            .onChange(of: model.selectedBackup) { _ in
                // A password typed for one backup must not be carried over to another.
                if !model.busy && !model.password.isEmpty { model.password = "" }
            }
            .onChange(of: model.busy) { busy in
                if busy {
                    ui.jobDeviceID = model.selectedDevice
                    ui.jobDeviceName = model.chosenDevice?.name ?? ""
                } else if model.operation == .restore && !model.password.isEmpty {
                    // However the restore ended, do not keep the backup password around.
                    model.password = ""
                }
            }
    }

    /// Tells the model which device or backup the user is looking at.
    private func push(_ item: SidebarItem?) {
        guard let item = item else { return }
        switch item {
        case .device(let id):
            if model.selectedDevice != id { model.selectedDevice = id }
        case .backup(let id):
            if model.selectedBackup != id { model.selectedBackup = id }
        }
    }
}

/// The confirmation dialog for destructive actions and the two sheets.
struct Dialogs: ViewModifier {
    @EnvironmentObject var model: Model
    @EnvironmentObject var ui: WindowState

    private var confirming: Binding<Bool> {
        Binding(
            get: { ui.confirmation != nil },
            set: { showing in
                if !showing { ui.confirmation = nil }
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                ui.confirmation?.title ?? "",
                isPresented: confirming,
                titleVisibility: .visible,
                presenting: ui.confirmation
            ) { item in
                Button(item.confirmLabel, role: .destructive) {
                    item.perform(model)
                }
                Button(item.keepLabel, role: .cancel) { }
            } message: { item in
                Text(item.message(model))
            }
            .sheet(isPresented: $ui.showRestoreConfirm) {
                RestoreConfirmSheet()
                    .environmentObject(model)
                    .environmentObject(ui)
            }
            .sheet(item: $ui.encryptionTask) { task in
                EncryptionSheet(kind: task)
                    .environmentObject(model)
                    .environmentObject(ui)
            }
    }
}

// MARK: - Detail column

struct DetailView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var ui: WindowState

    private var shownDevice: Device? {
        guard case .some(.device(let id)) = ui.selection else { return nil }
        return model.devices.first { $0.id == id }
    }

    private var shownBackup: Backup? {
        guard case .some(.backup(let id)) = ui.selection else { return nil }
        return model.backups.first { $0.id == id }
    }

    var body: some View {
        page
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ActivityPanel()
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    refreshButton
                    backUpButton
                    restoreButton
                }
            }
    }

    private var backUpHelp: String {
        if let problem = model.backupProblem() { return problem }
        if let device = model.chosenDevice { return "Back up “\(device.name)” now" }
        return "Back up the selected device now"
    }

    private var restoreHelp: String {
        if let problem = model.restoreProblem() { return problem }
        return "Restore the chosen backup onto the selected device"
    }

    private var refreshButton: some View {
        Button {
            ui.refreshAll(model)
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .help("Look for devices and backups again")
    }

    private var backUpButton: some View {
        Button {
            ui.requestBackup(model)
        } label: {
            Label("Back Up Now", systemImage: "arrow.down.doc")
        }
        .help(backUpHelp)
        .disabled(model.chosenDevice == nil || !model.canStart)
    }

    private var restoreButton: some View {
        Button {
            ui.requestRestore(model)
        } label: {
            Label("Restore…", systemImage: "clock.arrow.circlepath")
        }
        .help(restoreHelp)
        .disabled(model.chosenDevice == nil || !model.canStart)
    }

    @ViewBuilder private var page: some View {
        if let device = shownDevice {
            DeviceDetailView(device: device)
        } else if let backup = shownBackup {
            BackupDetailView(backup: backup)
        } else if model.devices.isEmpty {
            NoDeviceView()
                .navigationTitle("PhoneVault")
        } else {
            NothingSelectedView()
                .navigationTitle("PhoneVault")
        }
    }
}
