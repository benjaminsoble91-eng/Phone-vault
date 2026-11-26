import SwiftUI
import AppKit

// AppModelDeviceActions.swift
// The short device actions of Model: pair, unpair, restart, shut down, enter and leave recovery mode.
// Each runs one tool for a few seconds and reports through `actionBusy` and `actionMessage`.
//
// Command lines (checked against libimobiledevice 1.3.0, 1.4.0 and master, and libirecovery master):
//   idevicepair -u UDID pair | unpair
//   idevicediagnostics -u UDID restart | shutdown
//   ideviceenterrecovery UDID
//   irecovery -n

extension Model {

    /// Why a device action cannot run right now, or nil when it can.
    /// - Parameter tool: "idevicepair", "idevicediagnostics" or "ideviceenterrecovery".
    func deviceActionProblem(_ device: Device, tool: String) -> String? {
        if busy { return "Wait until the current job has finished." }
        if actionBusy { return "Wait until the current action has finished." }
        if !Tools.exists(tool) {
            return "\(tool) is not installed. Run \"\(Model.installCommand)\" in Terminal."
        }
        if !devices.contains(where: { $0.id == device.id }) {
            return "\(device.name) is no longer connected."
        }
        // Pairing is the one action that makes sense for a device that is not trusted yet.
        if tool != "idevicepair" && !device.trusted { return device.trust.explanation }
        return nil
    }

    /// Runs one tool in the background and publishes the sentence `summarize` makes of its result.
    func runAction(tool: String,
                   arguments: [String],
                   working: String,
                   timeout: TimeInterval,
                   finished: ((ToolResult) -> Void)? = nil,
                   summarize: @escaping (ToolResult) -> String) {
        actionBusy = true
        actionMessage = working
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Tools.run(tool, arguments, timeout: timeout)
            let message = summarize(result)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.actionBusy = false
                self.actionMessage = message
                finished?(result)
                self.refreshDevices(forceDetails: true)
            }
        }
    }

    /// Last line of a tool's output that says something, without a leading "ERROR: ".
    static func lastLine(of result: ToolResult) -> String {
        let lines = result.combined
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard var line = lines.last else { return "" }
        if line.hasPrefix("ERROR: ") { line = String(line.dropFirst("ERROR: ".count)) }
        return line
    }

    /// Advice for a failed action: a known problem if we recognise one, else what the tool said.
    static func failureText(_ what: String, _ result: ToolResult) -> String {
        if result.code == -1 && result.out.isEmpty { return "\(what): \(result.err)" }
        let lines = result.combined.split(whereSeparator: { $0.isNewline }).map { String($0) }
        if let hint = ErrorExplainer.hint(for: lines) { return "\(what). \(hint)" }
        let last = lastLine(of: result)
        if last.isEmpty { return "\(what). Unlock the phone, check the cable and try again." }
        return "\(what): \(last)"
    }

    // MARK: Pairing

    /// Starts pairing, which makes the Trust dialog appear on the phone.
    func pair(_ device: Device) {
        if let problem = deviceActionProblem(device, tool: "idevicepair") { actionMessage = problem; return }
        let name = device.trusted ? device.name : "the phone"
        let udid = device.id
        runAction(tool: "idevicepair",
                  arguments: ["-u", udid, "pair"],
                  working: "Pairing with \(name)...",
                  timeout: 30,
                  finished: { [weak self] result in
                      // Unless Trust was declined again, let the polling look at this device again.
                      if !result.combined.lowercased().contains("denied") { self?.quietDevices.remove(udid) }
                  }) { result in
            let lower = result.combined.lowercased()
            if lower.contains("success") { return "Paired with \(name)." }
            if lower.contains("trust dialog") && !lower.contains("denied") {
                return "Unlock the phone and tap Trust. PhoneVault notices by itself when that is done."
            }
            if lower.contains("passcode is set") {
                return "The phone is locked. Unlock it with its passcode, then click Ask Again."
            }
            if lower.contains("denied the trust dialog") {
                return "Trust was declined on the phone. Unplug it, plug it back in and tap Trust."
            }
            return Model.failureText("Pairing failed", result)
        }
    }

    /// Removes the pairing between this Mac and the device. Put this behind a confirmation.
    func unpair(_ device: Device) {
        if let problem = deviceActionProblem(device, tool: "idevicepair") { actionMessage = problem; return }
        // Do not let the device list pair again by itself straight after this.
        pairTried.insert(device.id)
        let name = device.name
        let udid = device.id
        runAction(tool: "idevicepair",
                  arguments: ["-u", udid, "unpair"],
                  working: "Unpairing \(name)...",
                  timeout: 30,
                  finished: { [weak self] result in
                      // Show the device as not paired and keep the polling away from it: asking it for
                      // its details would start a new pairing and put the Trust prompt straight back up.
                      guard let self = self, result.combined.lowercased().contains("success") else { return }
                      self.quietDevices.insert(udid)
                      if let index = self.devices.firstIndex(where: { $0.id == udid }) {
                          self.devices[index].trusted = false
                          self.devices[index].trust = .notPaired
                      }
                  }) { result in
            if result.combined.lowercased().contains("success") {
                return "\(name) is no longer paired with this Mac. To pair again, click Ask Again or unplug it and plug it back in."
            }
            return Model.failureText("Unpairing failed", result)
        }
    }

    // MARK: Power

    /// Restarts the device. Put this behind a confirmation.
    func restart(_ device: Device) {
        if let problem = deviceActionProblem(device, tool: "idevicediagnostics") { actionMessage = problem; return }
        let name = device.name
        runAction(tool: "idevicediagnostics",
                  arguments: ["-u", device.id, "restart"],
                  working: "Restarting \(name)...",
                  timeout: 30) { result in
            if result.out.contains("Restarting device") { return "\(name) is restarting." }
            return Model.failureText("\(name) did not restart", result)
        }
    }

    /// Powers the device off. Put this behind a confirmation.
    func shutDown(_ device: Device) {
        if let problem = deviceActionProblem(device, tool: "idevicediagnostics") { actionMessage = problem; return }
        let name = device.name
        runAction(tool: "idevicediagnostics",
                  arguments: ["-u", device.id, "shutdown"],
                  working: "Shutting down \(name)...",
                  timeout: 30) { result in
            if result.out.contains("Shutting down device") { return "\(name) is shutting down." }
            return Model.failureText("\(name) did not shut down", result)
        }
    }

    // MARK: Recovery mode

    /// Puts the device into recovery mode. It then shows the "connect to computer" screen and leaves the
    /// device list until it is told to boot normally again. Put this behind a confirmation.
    func enterRecovery(_ device: Device) {
        if let problem = deviceActionProblem(device, tool: "ideviceenterrecovery") { actionMessage = problem; return }
        let name = device.name
        let canLeave = Tools.exists("irecovery")
        runAction(tool: "ideviceenterrecovery",
                  arguments: [device.id],
                  working: "Putting \(name) into recovery mode...",
                  timeout: 30) { result in
            if result.out.contains("successfully switching to recovery mode") {
                let way = canLeave
                    ? "Use Exit Recovery Mode to start it normally again."
                    : "To leave recovery mode, hold the buttons for a forced restart until the Apple logo appears."
                return "\(name) is entering recovery mode and will disappear from the list. \(way)"
            }
            return Model.failureText("\(name) did not enter recovery mode", result)
        }
    }

    /// Tells a device that is in recovery mode to start normally (irecovery -n). Needs the irecovery tool.
    func exitRecovery() {
        if busy { actionMessage = "Wait until the current job has finished."; return }
        if actionBusy { actionMessage = "Wait until the current action has finished."; return }
        if !Tools.exists("irecovery") {
            actionMessage = "irecovery is not installed. Run \"brew install libirecovery\" in Terminal, or hold the buttons for a forced restart."
            return
        }
        runAction(tool: "irecovery",
                  arguments: ["-n"],
                  working: "Telling the phone to leave recovery mode...",
                  timeout: 30) { result in
            if result.ok { return "The phone was told to leave recovery mode. It should start normally now." }
            let lower = result.combined.lowercased()
            if lower.contains("unable to connect") || lower.contains("no device") {
                return "No phone in recovery mode was found."
            }
            return Model.failureText("The phone did not leave recovery mode", result)
        }
    }
}
