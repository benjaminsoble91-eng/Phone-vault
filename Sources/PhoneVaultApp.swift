import SwiftUI
import AppKit

// PhoneVaultApp.swift
// Entry point: one window, the shared Model, the view-side WindowState and the menu commands.

@main
struct PhoneVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = Model()
    @StateObject private var ui = WindowState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(ui)
                .frame(minWidth: 920, minHeight: 600)
                .modifier(AppearanceSync())
                .onAppear {
                    appDelegate.model = model
                }
        }
        .commands {
            PhoneVaultCommands(model: model, ui: ui)
        }
    }
}

/// Asks before quitting while a backup, restore or encryption change is running,
/// and keeps the app (and a running job) alive when the window is closed.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: Model?

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppAppearance.saved.apply()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = model, model.busy else { return .terminateNow }

        let alert = NSAlert()
        alert.alertStyle = .warning
        if model.operation == .restore {
            alert.messageText = "A restore is still running."
            alert.informativeText = "Quitting now stops it and can leave the device with only part of its data restored. You would have to run the restore again from the start."
        } else if model.operation == .backup {
            alert.messageText = "A backup is still running."
            alert.informativeText = "Quitting now stops it. The backup will be unfinished and cannot be restored until you back up again."
        } else {
            alert.messageText = "PhoneVault is still working on the device."
            alert.informativeText = "Quitting now stops the change to backup encryption before it is finished."
        }
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit Anyway")
        let answer = alert.runModal()
        return answer == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
    }
}
