import SwiftUI
import AppKit

// EncryptionSheet.swift
// One sheet for the three changes to a device's backup encryption: turn on, change password, turn off.
// Passwords live in @State only while the sheet is open; they are wiped when it is submitted or closed,
// and they are never shown, logged or stored.
//
// Turning encryption off is destructive, and this sheet is its confirmation: it states the consequence,
// needs the current password and has a red button that says what it does.

struct EncryptionSheet: View {
    @EnvironmentObject var model: Model
    @Environment(\.dismiss) private var dismiss
    let kind: EncryptionTask

    @State private var current = ""
    @State private var fresh = ""
    @State private var again = ""
    /// UDID and name of the device the sheet was opened for, so a change of device cannot go unnoticed.
    @State private var openedFor: String?
    @State private var openedName = ""

    private var deviceName: String {
        if !openedName.isEmpty { return openedName }
        return model.chosenDevice?.name ?? "the device"
    }

    private var title: String {
        switch kind {
        case .turnOn: return "Encrypt backups of “\(deviceName)”"
        case .changePassword: return "Change the backup password of “\(deviceName)”"
        case .turnOff: return "Turn off backup encryption for “\(deviceName)”?"
        }
    }

    private var explanation: String {
        switch kind {
        case .turnOn:
            return "From now on every backup of this device is protected with this password, whichever Mac or app makes it. Encrypted backups also include saved passwords, Wi-Fi settings, Health data and call history."
        case .changePassword:
            return "Backups made from now on use the new password. Backups that already exist keep the password they were made with."
        case .turnOff:
            return "Backups made from now on are not protected: anyone who can read the backup folder can read the data. They also leave out saved passwords, Wi-Fi settings, Health data and call history. Backups that are already encrypted stay encrypted with their password."
        }
    }

    private var caution: String {
        switch kind {
        case .turnOn, .changePassword:
            return "Write the password down. If it is lost, nobody can restore these backups, and the only way to remove it is to reset all settings on the device."
        case .turnOff:
            return ""
        }
    }

    private var needsCurrent: Bool { return kind != .turnOn }
    private var needsNew: Bool { return kind != .turnOff }

    /// What stops the form from being submitted, in words; nil when it is ready.
    private var formProblem: String? {
        if let id = openedFor, model.selectedDevice != id {
            return "“\(openedName)” is no longer connected or selected. Close this and start again."
        }
        if let problem = model.encryptionProblem() { return problem }
        if needsCurrent && current.isEmpty { return "Enter the current backup password." }
        if needsNew {
            if fresh.isEmpty { return "Enter a new password." }
            if again.isEmpty { return "Enter the new password a second time." }
            if fresh != again { return "The two new passwords are not the same." }
            if needsCurrent && fresh == current { return "The new password is the same as the current one." }
        }
        return nil
    }

    private var confirmLabel: String {
        switch kind {
        case .turnOn: return "Turn On Encryption"
        case .changePassword: return "Change Password"
        case .turnOff: return "Turn Off Encryption"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            EncryptionSheetHeader(title: title, explanation: explanation, destructive: kind == .turnOff)
            fields
            if !caution.isEmpty {
                Notice(.warning, caution)
            }
            if !model.passwordNote.isEmpty {
                Notice(.warning, model.passwordNote)
            }
            Notice(.info, "The device may ask for its passcode to allow this. Keep it unlocked and nearby.")
            if let problem = formProblem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
        }
        .padding(22)
        .frame(width: 500)
        .onAppear {
            if openedFor == nil {
                openedFor = model.selectedDevice
                openedName = model.chosenDevice?.name ?? ""
            }
        }
        .onDisappear { wipe() }
    }

    private var fields: some View {
        Form {
            if needsCurrent {
                SecureField("Current password", text: $current)
            }
            if needsNew {
                SecureField("New password", text: $fresh)
                SecureField("New password again", text: $again)
            }
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) {
                wipe()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            confirmButton
        }
    }

    @ViewBuilder private var confirmButton: some View {
        if kind == .turnOff {
            Button(confirmLabel, role: .destructive) { submit() }
                .disabled(formProblem != nil)
        } else {
            Button(confirmLabel) { submit() }
                .keyboardShortcut(.defaultAction)
                .disabled(formProblem != nil)
        }
    }

    private func wipe() {
        current = ""
        fresh = ""
        again = ""
    }

    private func submit() {
        guard formProblem == nil else { return }
        let oldPassword = current
        let newPassword = fresh
        wipe()
        switch kind {
        case .turnOn:
            model.enableEncryption(password: newPassword)
        case .changePassword:
            model.changeEncryptionPassword(old: oldPassword, new: newPassword)
        case .turnOff:
            model.disableEncryption(password: oldPassword)
        }
        dismiss()
    }
}

struct EncryptionSheetHeader: View {
    let title: String
    let explanation: String
    let destructive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: destructive ? "lock.open" : "lock.shield")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
