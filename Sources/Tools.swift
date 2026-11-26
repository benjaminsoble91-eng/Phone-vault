import Foundation

// Tools.swift
// Finds and runs the libimobiledevice command-line tools.
// Nothing in this file touches the UI, so every function may be called from a background queue.

/// Result of running a tool to completion.
struct ToolResult {
    /// Exit status, or -1 when the tool could not be started.
    let code: Int32
    /// Everything the tool wrote to standard output.
    let out: String
    /// Everything the tool wrote to standard error.
    let err: String

    var ok: Bool { return code == 0 }

    /// Standard output followed by standard error.
    var combined: String {
        if err.isEmpty { return out }
        if out.isEmpty { return err }
        return out + "\n" + err
    }
}

/// Small reference box so a background reader can hand its data back.
final class DataBox {
    var data = Data()
}

enum Tools {
    /// Folders searched for the tools, Homebrew on Apple Silicon first.
    static let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin"]

    /// Tools the app cannot work without.
    static let required = ["idevice_id", "ideviceinfo", "idevicebackup2"]

    /// Tools used by optional features (pairing, restart, shut down, recovery mode).
    static let optional = ["idevicepair", "idevicediagnostics", "ideviceenterrecovery", "irecovery"]

    /// Environment variable names idevicebackup2 reads passwords from (1.4.0 and newer).
    static let passwordVariables = ["BACKUP_PASSWORD", "BACKUP_PASSWORD_NEW"]

    static func path(_ name: String) -> String? {
        for d in dirs {
            let p = d + "/" + name
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    static func exists(_ name: String) -> Bool {
        return path(name) != nil
    }

    /// The environment handed to every tool: ours, minus any stray password variables, plus `extra`.
    static func environment(adding extra: [String: String]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for key in passwordVariables { env.removeValue(forKey: key) }
        for (key, value) in extra { env[key] = value }
        return env
    }

    /// Runs a tool and waits for it to finish.
    /// - Parameters:
    ///   - env: extra environment variables (used for passwords, never logged).
    ///   - timeout: seconds after which the tool is stopped; 0 means wait forever.
    static func run(_ name: String, _ args: [String], env: [String: String] = [:], timeout: TimeInterval = 0) -> ToolResult {
        guard let tool = path(name) else {
            return ToolResult(code: -1, out: "", err: name + " is not installed.")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.environment = environment(adding: env)
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            return ToolResult(code: -1, out: "", err: "Could not start " + name + ".")
        }
        if timeout > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if p.isRunning { p.terminate() }
            }
        }
        // Read standard error on another queue so neither pipe can fill up and block the tool.
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        return ToolResult(code: p.terminationStatus,
                          out: String(decoding: outData, as: UTF8.self),
                          err: String(decoding: errBox.data, as: UTF8.self))
    }

    /// What we learned about the installed idevicebackup2.
    struct BackupToolInfo {
        /// For example "1.4.0", or "" when unknown.
        var version: String
        /// True when the tool reads BACKUP_PASSWORD / BACKUP_PASSWORD_NEW (added April 2022, released in 1.4.0).
        /// When false, passwords have to be passed as command-line arguments (the only way in 1.3.0).
        var passwordsViaEnvironment: Bool
    }

    /// Asks idevicebackup2 for its version and checks its help text for the password environment variables.
    static func backupToolInfo() -> BackupToolInfo {
        var info = BackupToolInfo(version: "", passwordsViaEnvironment: false)
        let versionResult = run("idevicebackup2", ["--version"], timeout: 10)
        if versionResult.code == 0 {
            // Output looks like "idevicebackup2 1.4.0".
            let line = versionResult.out.trimmingCharacters(in: .whitespacesAndNewlines)
            if let last = line.split(separator: " ").last, line.hasPrefix("idevicebackup2") {
                info.version = String(last)
            }
        }
        let help = run("idevicebackup2", ["--help"], timeout: 10)
        info.passwordsViaEnvironment = help.combined.contains("BACKUP_PASSWORD")
        return info
    }
}
