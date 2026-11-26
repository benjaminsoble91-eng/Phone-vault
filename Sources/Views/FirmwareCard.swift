import SwiftUI
import AppKit

// FirmwareCard.swift
// "Install iOS" on a device page: install an IPSW file or the newest signed version,
// as an Update (keeps data) or Erase and Install. Runs idevicerestore.

struct FirmwareCard: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var ui: WindowState
    let device: Device

    var body: some View {
        Card("Install iOS", systemImage: "arrow.triangle.2.circlepath") {
            if model.toolAvailable("idevicerestore") {
                FirmwareOptions()
                FirmwareStartRow(device: device)
            } else {
                FirmwareToolMissing()
            }
        }
    }
}

/// Source (file or newest signed) and mode (update or erase). Shared with the recovery-mode help.
struct FirmwareOptions: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var ui: WindowState

    private var fileLine: String {
        if model.ipswPath.isEmpty { return "No file chosen" }
        var text = model.ipswName
        if let size = model.ipswSize { text += " · " + Format.bytes(size) }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InfoRow("Install") {
                Picker("Install", selection: $model.firmwareLatest) {
                    Text("IPSW File").tag(false)
                    Text("Newest Signed Version").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            if !model.firmwareLatest {
                InfoRow("File") {
                    Text(fileLine)
                        .foregroundStyle(model.ipswPath.isEmpty ? Color.secondary : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(model.ipswPath)
                    Button(model.ipswPath.isEmpty ? "Choose…" : "Change…") { ui.chooseIPSW(model) }
                }
            } else {
                InfoRow("") {
                    Text("Downloaded from Apple when you start. IPSW files are several gigabytes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            InfoRow("Mode") {
                Picker("Mode", selection: $model.firmwareErase) {
                    Text("Update").tag(false)
                    Text("Erase and Install").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            InfoRow("") {
                Text(model.firmwareErase
                     ? "Wipes everything on the device, then installs iOS. Like a new device afterwards."
                     : "Installs iOS and keeps apps, photos and settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Notice(.info, "Only iOS versions Apple is still signing for this device can be installed. Older versions need saved blobs and a tool such as turdus merula.")
        }
    }
}

struct FirmwareStartRow: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var ui: WindowState
    let device: Device

    private var problem: String? {
        return model.firmwareProblem(device: device)
    }

    /// "Choose an IPSW" is not shown as a problem: the button itself asks for the file.
    private var shownProblem: String? {
        guard let problem = problem else { return nil }
        if !model.firmwareLatest && model.ipswPath.isEmpty { return nil }
        return problem
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.firmwareErase {
                Notice(.warning, "Erase and Install deletes everything on “\(device.name)”. Back it up first.")
            }
            if let shown = shownProblem {
                Notice(.warning, shown)
            }
            HStack(spacing: 10) {
                Button {
                    ui.requestFirmware(model, device: device)
                } label: {
                    Label(model.firmwareErase ? "Erase and Install…" : "Install iOS…", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(model.firmwareErase ? Color.red : Color.accentColor)
                .disabled(!model.canStart || (shownProblem != nil))
                Text("Takes 15 minutes or more. Keep the device plugged in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FirmwareToolMissing: View {
    @EnvironmentObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Install iOS from an IPSW file, or the newest version Apple signs, with Update or Erase and Install. This needs one more free tool:")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            CommandBox(command: Model.firmwareInstallCommand)
            Button("Check Again") { model.checkTools() }
        }
    }
}
