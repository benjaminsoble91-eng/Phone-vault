import Foundation

// OutputParser.swift
// Turns the raw output of idevicebackup2 into progress numbers, log lines and plain-language hints.
// Pure logic with no UI and no shared state.
//
// Two output styles exist and both are handled:
//
//  * 1.3.0 and 1.4.0 redraw one line with carriage returns:
//        "\r[=========        ]  42%"                      overall progress, followed by " Finished\n"
//        "\r[====             ]  17% (1.2 MB/7.0 MB)     "  progress of the current file
//
//  * Builds newer than 1.4.0 draw a four-line block using ANSI escape codes:
//        "Backup     [########......] 42%"                   overall progress
//        "Receiving  <file name>"                            (or "Sending    <file name>")
//        "           [=====>        ]  17.3%   1.2 MB / 7.0 MB"
//        "Status     Receiving files"

/// What one chunk of output contained.
struct ParsedOutput {
    /// Overall progress 0...1, when the chunk reported one.
    var overall: Double?
    /// Progress of the current file 0...1.
    var file: Double?
    /// Name of the file being transferred (newer builds only).
    var fileName: String?
    /// Text of the status line (newer builds only).
    var stage: String?
    /// Ordinary lines for the log, in order.
    var lines: [String] = []
}

struct OutputParser {
    /// Unfinished text left over from the previous chunk.
    private var carry = ""

    mutating func reset() {
        carry = ""
    }

    /// Feeds the next chunk of tool output and returns what it contained.
    mutating func feed(_ text: String) -> ParsedOutput {
        var parsed = ParsedOutput()
        var buffer = carry + text
        // Every ANSI escape sequence (cursor save/restore/up, clear line) acts as a line break.
        buffer = buffer.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "\n", options: .regularExpression)
        var pieces = buffer.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
        // The last piece has no terminator yet; keep it for the next chunk.
        carry = pieces.isEmpty ? "" : pieces.removeLast()
        if carry.count > 8000 { carry = "" }
        for piece in pieces {
            classify(piece, into: &parsed)
        }
        return parsed
    }

    /// Returns whatever is still waiting in the buffer (call once when the tool has exited).
    mutating func flush() -> ParsedOutput {
        var parsed = ParsedOutput()
        let rest = carry
        carry = ""
        classify(rest, into: &parsed)
        return parsed
    }

    private func classify(_ piece: String, into parsed: inout ParsedOutput) {
        let line = piece.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { return }
        // A lone escape character left over from a split sequence.
        if line == "\u{1B}" { return }

        // Newer builds, line 1: "Backup     [####....] 42%"
        if line.range(of: "^Backup\\s+\\[[#.]*\\]\\s*[0-9]{1,3}%", options: .regularExpression) != nil {
            if let p = OutputParser.percent(in: line) { parsed.overall = p.value }
            return
        }
        // Newer builds, line 4: "Status     text"
        if line == "Status" { return }
        if line.hasPrefix("Status     ") {
            let text = String(line.dropFirst("Status".count)).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { parsed.stage = text }
            return
        }
        // Newer builds, line 2: "Receiving  name" / "Sending    name"
        if line == "Receiving" || line == "Sending" { return }
        if line.hasPrefix("Receiving  ") {
            parsed.fileName = String(line.dropFirst("Receiving".count)).trimmingCharacters(in: .whitespaces)
            return
        }
        if line.hasPrefix("Sending    ") {
            parsed.fileName = String(line.dropFirst("Sending".count)).trimmingCharacters(in: .whitespaces)
            return
        }
        // A progress bar: old overall bar, old per-file bar, or the newer per-file bar.
        if line.hasPrefix("["), let p = OutputParser.percent(in: line) {
            if p.hasDecimals || p.rest.contains("(") || p.rest.contains("/") {
                parsed.file = p.value
            } else {
                parsed.overall = p.value
            }
            return
        }
        parsed.lines.append(line)
    }

    /// Finds "] 42%" in a progress line. `value` is 0...1, `rest` is the text after the percent sign.
    static func percent(in line: String) -> (value: Double, hasDecimals: Bool, rest: String)? {
        guard let range = line.range(of: "\\]\\s*[0-9]{1,3}(\\.[0-9]+)?%", options: .regularExpression) else { return nil }
        let token = String(line[range].filter { $0.isNumber || $0 == "." })
        guard let number = Double(token) else { return nil }
        let rest = String(line[range.upperBound...])
        return (min(max(number / 100, 0), 1), token.contains("."), rest)
    }
}

// MARK: - Plain-language explanations

enum ErrorExplainer {
    /// Looks through the tool's output for a problem we recognise and returns advice for the user,
    /// or nil when nothing familiar was found. Later lines win over earlier ones.
    static func hint(for lines: [String]) -> String? {
        var found: String?
        for line in lines {
            if let h = hint(forLine: line) { found = h }
        }
        return found
    }

    static func hint(forLine line: String) -> String? {
        let lower = line.lowercased()

        // Messages printed by idevicebackup2 itself (verified in its source).
        if lower.contains("no device found") {
            return "The phone is no longer connected. Check the cable and try again."
        }
        if lower.contains("could not connect to lockdownd") {
            switch DeviceQuery.trustState(fromFailure: line) {
            case .locked: return "The phone is locked. Unlock it with its passcode and try again."
            case .needsTrust: return "Unlock the phone and tap Trust, then try again."
            case .denied: return "Trust was declined on the phone. Unplug it, plug it back in and tap Trust."
            case .notPaired: return "The phone is not paired with this Mac. Choose Device > Ask the Device to Trust This Mac, tap Trust on the phone, then try again."
            default: return "The Mac could not talk to the phone. Unlock it, check the cable and try again."
            }
        }
        if lower.contains("a backup password is required") {
            return "This backup is encrypted. Enter its password and try again."
        }
        if lower.contains("cannot ensure we restore from a successful backup") || lower.contains("could not read status.plist") {
            return "This backup was never finished, so it cannot be restored. Pick another backup."
        }
        if lower.contains("is invalid. no info.plist found") || lower.contains("is invalid. no manifest.plist found") {
            return "This folder is not a complete backup."
        }
        if lower.contains("backup directory") && lower.contains("does not exist") {
            return "The backup folder is missing."
        }
        if lower.contains("backup encryption is already enabled") {
            return "Backup encryption is already on for this phone."
        }
        if lower.contains("backup encryption is not enabled") {
            return "Backup encryption is not on for this phone."
        }
        if lower.contains("could not enable backup encryption") {
            return "The phone did not turn on backup encryption. Keep it unlocked and enter the passcode on the phone if it asks."
        }
        if lower.contains("could not disable backup encryption") || lower.contains("could not change backup encryption password") {
            return "The phone refused. The current backup password is probably wrong, or the passcode was not entered on the phone."
        }
        if lower.contains("device refused to start the") {
            return "The phone refused to start. Unlock it, keep it on the Home Screen and try again."
        }
        if lower.contains("could not receive from mobilebackup2") {
            return "The connection to the phone was lost. Check the cable, keep the phone unlocked and try again."
        }
        if lower.contains("could not start service") {
            return "The phone would not start its backup service. Unlock it, and restart the phone if this keeps happening."
        }
        if lower.contains("timeout while locking for sync") || lower.contains("could not lock file") {
            return "The phone is busy syncing with something else. Wait a moment and try again."
        }
        if lower.contains("no space left on device") {
            return "This Mac's disk is full. Free up space and try again."
        }

        // Errors reported by the phone ("ErrorCode N: description"). The wording comes from iOS,
        // so these are matched loosely by keyword.
        if lower.hasPrefix("errorcode") {
            if lower.contains("find my") {
                return "Find My is on. On the phone open Settings > your name > Find My and turn off Find My iPhone, then try again."
            }
            if lower.contains("password") {
                return "The backup password is wrong."
            }
            if lower.contains("locked") || lower.contains("passcode") {
                return "The phone is locked. Unlock it, keep it awake and try again."
            }
            if lower.contains("space") || lower.contains("storage") {
                return "There is not enough free space. Check free space on the phone and on this Mac."
            }
            if lower.contains("cancel") {
                return "The operation was cancelled on the phone."
            }
        }
        return nil
    }

    /// Lines that ask the user to do something on the phone while the job is still running.
    static func prompt(forLine line: String) -> String? {
        let lower = line.lowercased()
        if lower.contains("waiting for passcode to be entered on the device") || lower.contains("by entering the passcode on the device") {
            return "Enter the passcode on the phone to continue."
        }
        return nil
    }
}

/// What the final lines of idevicebackup2 say about how the job ended.
enum ToolVerdict {
    case success
    case failure
    case aborted
    case unknown

    /// Checks one output line. The strings are the ones idevicebackup2 prints in 1.3.0, 1.4.0 and newer.
    static func from(line: String) -> ToolVerdict {
        if line.hasSuffix("Successful.") || line.hasSuffix("successfully.") { return .success }
        if line.hasSuffix("Aborted.") || line.contains("User has cancelled the backup process on the device") { return .aborted }
        if line.contains("Backup Failed") || line.contains("Restore Failed") || line.contains("Operation Failed") { return .failure }
        if line.hasPrefix("Could not enable") || line.hasPrefix("Could not disable") || line.hasPrefix("Could not change backup encryption") { return .failure }
        return .unknown
    }
}
