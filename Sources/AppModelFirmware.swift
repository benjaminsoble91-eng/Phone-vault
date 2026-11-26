import Foundation

// AppModelFirmware.swift
// Installing iOS from an IPSW (or the newest version Apple signs) with idevicerestore.
// Update keeps the device's data; Erase wipes it first. Only versions Apple is still signing
// for the device can be installed: idevicerestore asks Apple's signing server for each install.

extension Model {

    static let firmwareInstallCommand = "brew install idevicerestore"

    /// Display name of the chosen IPSW file, or "".
    var ipswName: String {
        if ipswPath.isEmpty { return "" }
        return (ipswPath as NSString).lastPathComponent
    }

    /// Size of the chosen IPSW file, when it can be read.
    var ipswSize: Int64? {
        guard !ipswPath.isEmpty,
              let attributes = try? FileManager.default.attributesOfItem(atPath: ipswPath),
              let size = attributes[.size] as? NSNumber else { return nil }
        return size.int64Value
    }

    /// Why installing iOS cannot start now, or nil when it can.
    /// - Parameter device: the connected device to install on, or nil for a device in recovery mode.
    func firmwareProblem(device: Device?) -> String? {
        if !toolAvailable("idevicerestore") {
            return "Installing iOS needs one more tool. Run \"\(Model.firmwareInstallCommand)\" in Terminal, then click Check Again."
        }
        if busy { return "Wait until the current job has finished." }
        if actionBusy { return "Wait until the current action has finished." }
        if let device = device, !device.trusted { return device.trust.explanation }
        if !firmwareLatest {
            if ipswPath.isEmpty { return "Choose an IPSW file, or pick Latest Signed Version." }
            if !FileManager.default.fileExists(atPath: ipswPath) {
                return "The chosen IPSW file is no longer at \(ipswPath). Choose it again."
            }
            if !ipswPath.lowercased().hasSuffix(".ipsw") {
                var isFolder: ObjCBool = false
                FileManager.default.fileExists(atPath: ipswPath, isDirectory: &isFolder)
                if !isFolder.boolValue { return "That file is not an IPSW. Choose a file ending in .ipsw." }
            }
        }
        return nil
    }

    /// Starts installing iOS.
    /// - Parameters:
    ///   - udid: the connected device (normal mode), or nil to let idevicerestore find a device in recovery or DFU mode.
    ///   - deviceName: for the status texts.
    func startFirmwareInstall(udid: String?, deviceName: String) {
        if busy { return }
        if let problem = firmwareProblem(device: udid.flatMap { id in devices.first { $0.id == id } }) {
            failBeforeStart(kind: .firmware, status: "Installing iOS could not start.", hint: problem)
            return
        }
        // -y: no questions on the command line. PhoneVault asks its own confirmation before this point.
        var arguments: [String] = ["-y"]
        if let udid = udid { arguments += ["-u", udid] }
        if firmwareErase { arguments.append("-e") }
        if firmwareLatest {
            arguments.append("-l")
        } else {
            arguments.append(ipswPath)
        }
        let what = firmwareLatest ? "the newest signed iOS" : ipswName
        let mode = firmwareErase ? "erase and install" : "update, keeping data"
        let job = JobRequest(kind: .firmware,
                             tool: "idevicerestore",
                             pseudoTerminal: false,
                             arguments: arguments,
                             udid: udid ?? "",
                             deviceName: deviceName,
                             startStatus: "Installing \(what) on \(deviceName)…",
                             startStage: firmwareLatest ? "Finding the newest version Apple signs…" : "Reading the IPSW…",
                             logHeader: "Installing \(what) (\(mode)) with idevicerestore")
        run(job)
    }

    /// Plain-language reason for a failed install, read from idevicerestore's output.
    static func firmwareHint(_ lines: [String]) -> String {
        let text = lines.joined(separator: "\n").lowercased()
        if text.contains("isn't eligible") || text.contains("not eligible") || text.contains("unable to get shsh")
            || text.contains("unable to send tss") || text.contains("tss request") && text.contains("fail") {
            return "Apple is not signing this iOS version for this device any more, so it cannot be installed. Pick the newest signed version instead."
        }
        if text.contains("unable to discover device") || text.contains("no device found") || text.contains("unable to find device") {
            return "idevicerestore could not find the device. Check the cable, unlock the device, and try again."
        }
        if text.contains("does not support this device") || text.contains("not compatible") || text.contains("no build manifest") {
            return "This IPSW is not made for this device. Download the IPSW for its exact model."
        }
        if text.contains("unable to extract") || text.contains("corrupt") || text.contains("unable to open ipsw") {
            return "The IPSW could not be read. It may be damaged or incomplete; download it again."
        }
        if text.contains("unable to connect") || text.contains("timed out") || text.contains("lost connection") {
            return "The connection to the device dropped. Use a cable plugged straight into the Mac and try again. If the device shows a cable on a black screen, install again; it can be restored from there."
        }
        if let last = lines.last(where: { $0.lowercased().contains("error") }) {
            return "idevicerestore reported: \(last)"
        }
        return "idevicerestore stopped without saying why. If the device shows a cable on a black screen, install again; it can be restored from recovery mode."
    }
}

/// Turns idevicerestore's output into progress, a stage line and log lines.
/// Handles both the older "\r[=====    ]  42.0%" bars and the newer "Label:  42.0%" lines.
struct FirmwareParser {
    private var carry = ""

    mutating func reset() {
        carry = ""
    }

    mutating func feed(_ text: String) -> ParsedOutput {
        var out = ParsedOutput()
        let all = FirmwareParser.stripEscapes(carry + text)
        var pieces = all.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
        carry = pieces.removeLast()
        for piece in pieces {
            FirmwareParser.handle(piece, into: &out)
        }
        // A bar being redrawn without a line break still reports progress.
        if let value = FirmwareParser.percent(in: carry) {
            out.overall = value
            if let label = FirmwareParser.label(of: carry) { out.stage = label }
        }
        return out
    }

    mutating func flush() -> ParsedOutput {
        var out = ParsedOutput()
        let rest = carry
        carry = ""
        FirmwareParser.handle(rest, into: &out)
        return out
    }

    private static func handle(_ raw: String, into out: inout ParsedOutput) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { return }
        if let value = percent(in: line) {
            out.overall = value
            if let label = label(of: line) { out.stage = label }
            return
        }
        out.lines.append(line)
        if let stage = stage(for: line) { out.stage = stage }
    }

    /// "42.0" in "Extracting filesystem [====    ]  42.0%" or "Verifying filesystem:  42.0%".
    static func percent(in line: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: "([0-9]{1,3}(?:\\.[0-9]+)?)\\s*%\\s*$") else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              let found = Range(match.range(at: 1), in: trimmed),
              let number = Double(trimmed[found]) else { return nil }
        return min(max(number / 100, 0), 1)
    }

    /// The words before the bar or the colon: "Verifying filesystem".
    static func label(of line: String) -> String? {
        var text = line.trimmingCharacters(in: .whitespaces)
        if let bracket = text.firstIndex(of: "[") {
            text = String(text[..<bracket])
        } else if let colon = text.lastIndex(of: ":") {
            text = String(text[..<colon])
        } else {
            return nil
        }
        text = text.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    /// Lines that say what idevicerestore is doing now.
    static func stage(for line: String) -> String? {
        let starts = ["Extracting", "Sending", "Waiting", "Entering", "Getting", "Requesting", "Downloading",
                      "Connecting", "Uploading", "Verifying", "Flashing", "Restoring", "Updating", "Checking", "Status:"]
        for prefix in starts where line.hasPrefix(prefix) {
            var text = line
            if text.hasPrefix("Status: ") { text = String(text.dropFirst(8)) }
            while text.hasSuffix(".") || text.hasSuffix(":") { text.removeLast() }
            return text.isEmpty ? nil : text + "…"
        }
        return nil
    }

    /// Removes terminal colour and cursor codes.
    static func stripEscapes(_ text: String) -> String {
        if !text.contains("\u{1B}") { return text }
        guard let regex = try? NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[A-Za-z]") else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}
