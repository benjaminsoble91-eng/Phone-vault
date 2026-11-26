import SwiftUI
import AppKit

// EmptyStates.swift
// What the window shows when there is nothing to work with yet:
// the tools are not installed, no device is connected, or nothing is selected.

/// Shared layout: icon tile, title, then whatever explains the next step.
/// Centred in the window when it fits; scrolls only when the window is too short for it.
struct EmptyStateLayout<Content: View>: View {
    private let systemImage: String
    private let title: String
    private let content: Content

    init(systemImage: String, title: String, @ViewBuilder content: () -> Content) {
        self.systemImage = systemImage
        self.title = title
        self.content = content()
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 18) {
            IconTile(systemImage: systemImage, size: 60)
            Text(title)
                .font(.title.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(36)
        .frame(maxWidth: 560, alignment: .leading)
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            column
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ScrollView {
                column
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Tools missing

/// Replaces the whole window until the required command-line tools are installed.
struct ToolsMissingView: View {
    @EnvironmentObject var model: Model

    private var missingText: String {
        if model.missingTools.isEmpty { return "" }
        return "Not found on this Mac: " + model.missingTools.joined(separator: ", ")
    }

    var body: some View {
        EmptyStateLayout(systemImage: "shippingbox", title: "PhoneVault needs one more thing installed") {
            Text(Model.installHelp)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            CommandBox(command: Model.installCommand)
            if !missingText.isEmpty {
                Text(missingText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            HStack(spacing: 10) {
                Button("Check Again") { model.checkTools() }
                    .keyboardShortcut(.defaultAction)
                Button("Open Terminal") { ToolsMissingView.openTerminal() }
                Button("Open brew.sh") { ToolsMissingView.openHomebrewSite() }
            }
            Text("Nothing is sent anywhere: the tools talk to your devices over the USB cable only.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func openTerminal() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open(url)
    }

    static func openHomebrewSite() {
        if let url = URL(string: "https://brew.sh") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - No device

struct NoDeviceView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        EmptyStateLayout(systemImage: "cable.connector", title: "Connect an iPhone or iPad") {
            VStack(alignment: .leading, spacing: 12) {
                StepLine(number: 1, text: "Plug the device into this Mac with a USB cable that can carry data.")
                StepLine(number: 2, text: "Unlock it with its passcode.")
                StepLine(number: 3, text: "When it asks “Trust This Computer?”, tap Trust and enter the passcode.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardBackground())
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text("Looking for devices every few seconds…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Look Again Now") { model.refreshDevices(forceDetails: true) }
                    .disabled(!model.canStart)
            }
            DisclosureGroup {
                RecoveryHelp()
                    .padding(.top, 8)
            } label: {
                Text("Device stuck on a black screen with a cable?")
                    .font(.callout)
            }
            if !model.backups.isEmpty {
                Label("Your backups are on the left. You can open, archive or remove them without a device connected.",
                      systemImage: "sidebar.left")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A device in recovery mode is not listed at all, so the way out is offered here.
struct RecoveryHelp: View {
    @EnvironmentObject var model: Model

    private var text: String {
        if model.toolAvailable("irecovery") {
            return "That screen means recovery mode, and a device in recovery mode is not listed. PhoneVault can tell it to start normally."
        }
        return "That screen means recovery mode, and a device in recovery mode is not listed. To let PhoneVault start it normally, install one more tool, then click Exit Recovery Mode:"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !model.toolAvailable("irecovery") {
                CommandBox(command: "brew install libirecovery")
            }
            Button("Exit Recovery Mode") { model.exitRecovery() }
                .disabled(!model.canStart)
        }
    }
}

// MARK: - Nothing selected

struct NothingSelectedView: View {
    var body: some View {
        EmptyStateLayout(systemImage: "sidebar.left", title: "Choose a device or a backup") {
            Text("Pick a device on the left to back it up or restore it, or pick a backup to see its details.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
