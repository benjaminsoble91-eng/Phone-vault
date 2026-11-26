import SwiftUI
import AppKit

// AppModelOperations.swift
// The long-running jobs of Model: backup, restore and the three backup-encryption changes.
// All of them run idevicebackup2 once, read its output while it runs and end in exactly one of
// three states: success, failure or cancelled.
//
// Command lines used here were checked against idevicebackup2.c of libimobiledevice 1.3.0, 1.4.0 and master:
//   idevicebackup2 -u UDID [--full] backup DIRECTORY
//   idevicebackup2 -u UDID [-s FOLDER] [--system] [--settings] [--no-reboot] [--skip-apps] [--remove] [--copy] restore DIRECTORY
//   idevicebackup2 -u UDID encryption on|off      (password in BACKUP_PASSWORD_NEW / BACKUP_PASSWORD)
//   idevicebackup2 -u UDID changepw               (old in BACKUP_PASSWORD, new in BACKUP_PASSWORD_NEW)
// Options are placed before the command word because 1.4.0 and newer parse them with getopt_long.
// 1.3.0 does not read the environment variables, so for that version only the passwords are passed
// as arguments ("--password PWD", "encryption on PWD", "encryption off PWD", "changepw OLD NEW").
//
// Passwords never reach the log, the status text or UserDefaults.

/// Everything needed to start idevicebackup2 once.
struct JobRequest {
    var kind: OperationKind
    /// Arguments for idevicebackup2. May contain a password when the installed tool is 1.3.0, so they are never logged.
    var arguments: [String]
    /// Extra environment variables (the passwords, for 1.4.0 and newer).
    var environment: [String: String] = [:]
    /// Passwords used by this job; blanked out should the tool ever echo one.
    var secrets: [String] = []
    /// UDID of the device the job works on.
    var udid: String
    /// Name of the device, for the status sentences.
    var deviceName: String
    /// Status line shown while the job runs.
    var startStatus: String
    /// Stage line shown until the tool reports something better.
    var startStage: String = ""
    /// First line of the log (must not contain a password).
    var logHeader: String
}

extension Model {

    // MARK: Texts

    static let installCommand = "brew install libimobiledevice"
    static let installHelp = "PhoneVault uses the free libimobiledevice tools to talk to iPhones. Install Homebrew from https://brew.sh if you do not have it, then run this in Terminal and press Check Again:"
    static let passcodePrompt = "Enter the passcode on the phone to continue."
    static let passcodeReminder = "Keep the phone unlocked. If it asks for its passcode, enter it."

    // MARK: Small helpers for the views

    /// True when no job and no short action is running and the tools are installed.
    var canStart: Bool { return !busy && !actionBusy && !toolsMissing }

    /// `elapsed` as "1:05" or "1:02:03".
    var elapsedText: String { return Format.duration(elapsed) }

    /// Warning for password fields when the installed tool is too old to take passwords safely, else "".
    var passwordNote: String {
        if passwordsViaEnvironment || toolsMissing { return "" }
        return "Your idevicebackup2 is an old version that only accepts passwords on its command line, where other programs on this Mac can see them while it runs. Updating with \"brew upgrade libimobiledevice\" fixes that."
    }

    /// Whether an optional tool (idevicepair, idevicediagnostics, ideviceenterrecovery, irecovery) is installed.
    func toolAvailable(_ name: String) -> Bool {
        return Tools.exists(name)
    }

    /// Compares two version strings such as "17.5.1" and "18.0".
    /// Returns -1, 0 or 1, or nil when either one is not made of numbers and dots.
    static func compareVersions(_ a: String, _ b: String) -> Int? {
        guard let left = versionParts(a), let right = versionParts(b) else { return nil }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }

    static func versionParts(_ text: String) -> [Int]? {
        let pieces = text.split(separator: ".")
        if pieces.isEmpty { return nil }
        var parts: [Int] = []
        for piece in pieces {
            guard let number = Int(String(piece)) else { return nil }
            parts.append(number)
        }
        return parts
    }

    /// Reason shared by every job for not starting right now, or nil.
    func commonProblem() -> String? {
        if toolsMissing { return "The libimobiledevice tools are not installed." }
        if busy { return "Wait until the current job has finished." }
        if actionBusy { return "Wait until the current action has finished." }
        return nil
    }

    /// Reason the selected device cannot be used for a job, or nil.
    func deviceProblem() -> String? {
        guard let device = chosenDevice else {
            return devices.isEmpty ? "Connect an iPhone with a cable." : "Pick a device first."
        }
        if !device.trusted { return device.trust.explanation }
        return nil
    }

    // MARK: Backup

    /// Why Back Up cannot start now, or nil when it can.
    func backupProblem() -> String? {
        if let problem = commonProblem() { return problem }
        if let problem = deviceProblem() { return problem }
        if let problem = destinationProblem { return problem }
        return nil
    }

    /// Something worth telling the user before a backup that does not stop it, or nil.
    func backupWarning() -> String? {
        guard let free = destinationFree, let used = chosenDetails?.storageUsed else { return nil }
        if free < used {
            return "This Mac has \(Format.bytes(free)) free and the phone is using \(Format.bytes(used)). The backup may not fit."
        }
        return nil
    }

    /// Backs up the selected device into the chosen destination folder.
    func startBackup() {
        if let problem = backupProblem() { status = problem; return }
        guard let device = chosenDevice else { return }
        let root = destinationRoot
        let access = BackupStore.prepare(root)
        if destination == .finder && finderAccess != access { finderAccess = access }
        if access != .ok {
            let hint = destination == .finder
                ? Model.fullDiskAccessMessage
                : "PhoneVault could not create or open the folder \(root)."
            failBeforeStart(kind: .backup, status: "The backup could not start.", hint: hint)
            return
        }
        var arguments = ["-u", device.id]
        if forceFullBackup { arguments.append("--full") }
        arguments += ["backup", root]
        operationRoot = root
        let encrypted = details[device.id]?.backupEncryption == true
        run(JobRequest(kind: .backup,
                       arguments: arguments,
                       udid: device.id,
                       deviceName: device.name,
                       startStatus: "Backing up \(device.name)...",
                       startStage: Model.passcodeReminder,
                       logHeader: "Backup of \(device.name) (\(device.model), iOS \(device.version)) to \(root)"
                           + (encrypted ? " [encrypted by the phone]" : "")))
    }

    // MARK: Restore

    /// Why Restore cannot start now, or nil when it can.
    /// Covers the pre-checks: unfinished backup, backup made on a newer iOS than the phone runs,
    /// missing password for an encrypted backup, Find My still on.
    func restoreProblem() -> String? {
        if let problem = commonProblem() { return problem }
        if let problem = deviceProblem() { return problem }
        guard let device = chosenDevice else { return "Pick a device first." }
        guard let backup = chosenBackup else {
            return backups.isEmpty ? "There are no backups on this Mac yet." : "Pick a backup to restore."
        }
        if !FileManager.default.fileExists(atPath: backup.path + "/Manifest.plist") {
            return "That backup folder is missing or incomplete."
        }
        if !backup.complete {
            return "This backup was never finished, so it cannot be restored. Pick another backup."
        }
        if let order = Model.compareVersions(backup.version, device.version), order > 0 {
            return "This backup was made on iOS \(backup.version), but \(device.name) runs iOS \(device.version). A backup cannot be restored onto an older iOS. Update the phone first."
        }
        if details[device.id]?.findMy == true {
            return "Find My is on. On the phone open Settings > your name > Find My and turn off Find My iPhone, then try again."
        }
        if backup.encrypted && password.isEmpty {
            return "This backup is encrypted. Enter its password."
        }
        return nil
    }

    /// Things the user should read before confirming a restore. The first entry is always the data-loss warning.
    func restoreWarnings() -> [String] {
        var list: [String] = []
        guard let device = chosenDevice, let backup = chosenBackup else {
            return ["Restoring replaces the data on the phone with the contents of the backup."]
        }
        var first = "Restoring replaces the apps' data, messages, photos and settings on \(device.name) with the contents of this backup"
        if let date = backup.date { first += " from \(Format.date(date))" }
        first += ". Anything newer on the phone is lost."
        list.append(first)

        if backup.udid.lowercased() != device.id.lowercased() {
            list.append("This backup was made from a different device (\(backup.name), \(backup.model)). It will be put onto \(device.name).")
        }
        if !backup.model.isEmpty && !device.deviceClass.isEmpty {
            let backupIsPad = backup.model.hasPrefix("iPad")
            let deviceIsPad = device.deviceClass == "iPad"
            if backupIsPad != deviceIsPad {
                list.append("The backup comes from a different kind of device. Some content may not carry over.")
            }
        }
        if Model.compareVersions(backup.version, device.version) == nil {
            list.append("PhoneVault could not compare the iOS versions. The backup's iOS (\(backup.version)) must not be newer than the phone's (\(device.version)).")
        }
        let info = details[device.id]
        if info?.findMy == nil {
            list.append("PhoneVault could not check Find My. It must be off: Settings > your name > Find My > Find My iPhone.")
        }
        if backup.encrypted {
            list.append("This backup is encrypted. Afterwards the phone keeps encrypting its backups with the same password.")
        }
        if let total = info?.storageTotal, let size = backupSizes[backup.id], size > total {
            list.append("The backup (\(Format.bytes(size))) is larger than the phone's storage (\(Format.bytes(total))).")
        }
        if let battery = info?.batteryPercent, battery < 20, info?.charging != true {
            list.append("The phone's battery is at \(battery)%. Keep it plugged in.")
        }
        if restoreRemoveItems {
            list.append("\"Remove items not in the backup\" is on: content on the phone that the backup does not contain is deleted.")
        }
        if restoreReboot {
            list.append("The phone restarts when the restore is done. Do not unplug it until it is back on the Home Screen.")
        } else {
            list.append("The phone will not restart by itself. Restart it afterwards so the restored data is picked up.")
        }
        return list
    }

    /// DESTRUCTIVE: restores the selected backup onto the selected device. Put this behind a confirmation.
    func startRestore() {
        if let problem = restoreProblem() { status = problem; return }
        guard let device = chosenDevice, let backup = chosenBackup else { return }
        var arguments = ["-u", device.id]
        // The tool reads DIRECTORY/<UDID of the phone> unless told to use another folder name.
        if backup.folder != device.id { arguments += ["-s", backup.folder] }
        if restoreSystemFiles { arguments.append("--system") }
        if restoreSettings { arguments.append("--settings") }
        if !restoreReboot { arguments.append("--no-reboot") }
        if restoreSkipApps { arguments.append("--skip-apps") }
        if restoreRemoveItems { arguments.append("--remove") }
        if restoreCopyFirst { arguments.append("--copy") }
        var environment: [String: String] = [:]
        var secrets: [String] = []
        if backup.encrypted {
            secrets.append(password)
            if passwordsViaEnvironment {
                environment["BACKUP_PASSWORD"] = password
            } else {
                arguments += ["--password", password]
            }
        }
        arguments += ["restore", backup.root]
        operationRoot = backup.root
        var header = "Restore of the backup of \(backup.name) (iOS \(backup.version)"
        if let date = backup.date { header += ", \(Format.date(date))" }
        header += ") onto \(device.name) (iOS \(device.version))"
        run(JobRequest(kind: .restore,
                       arguments: arguments,
                       environment: environment,
                       secrets: secrets,
                       udid: device.id,
                       deviceName: device.name,
                       startStatus: "Restoring \(device.name)...",
                       startStage: "Keep the phone connected and unlocked.",
                       logHeader: header))
    }

    // MARK: Backup encryption (a setting stored on the phone)

    /// Why backup encryption cannot be changed now, or nil when it can.
    func encryptionProblem() -> String? {
        if let problem = commonProblem() { return problem }
        if let problem = deviceProblem() { return problem }
        return nil
    }

    /// Turns on backup encryption on the selected device with a new password.
    func enableEncryption(password newPassword: String) {
        if let problem = encryptionProblem() { status = problem; return }
        guard let device = chosenDevice else { return }
        if newPassword.isEmpty {
            failBeforeStart(kind: .encryptionOn, status: "Backup encryption was not changed.", hint: "Enter a password.")
            return
        }
        if details[device.id]?.backupEncryption == true {
            failBeforeStart(kind: .encryptionOn, status: "Backup encryption was not changed.",
                            hint: "Backup encryption is already on for this phone.")
            return
        }
        var arguments = ["-u", device.id, "encryption", "on"]
        var environment: [String: String] = [:]
        if passwordsViaEnvironment {
            environment["BACKUP_PASSWORD_NEW"] = newPassword
        } else {
            arguments.append(newPassword)
        }
        run(JobRequest(kind: .encryptionOn,
                       arguments: arguments,
                       environment: environment,
                       secrets: [newPassword],
                       udid: device.id,
                       deviceName: device.name,
                       startStatus: "Turning on backup encryption on \(device.name)...",
                       startStage: Model.passcodeReminder,
                       logHeader: "Turning on backup encryption on \(device.name)"))
    }

    /// Turns off backup encryption on the selected device. Needs the current backup password. Put this behind a confirmation.
    func disableEncryption(password currentPassword: String) {
        if let problem = encryptionProblem() { status = problem; return }
        guard let device = chosenDevice else { return }
        if currentPassword.isEmpty {
            failBeforeStart(kind: .encryptionOff, status: "Backup encryption was not changed.",
                            hint: "Enter the current backup password.")
            return
        }
        if details[device.id]?.backupEncryption == false {
            failBeforeStart(kind: .encryptionOff, status: "Backup encryption was not changed.",
                            hint: "Backup encryption is not on for this phone.")
            return
        }
        var arguments = ["-u", device.id, "encryption", "off"]
        var environment: [String: String] = [:]
        if passwordsViaEnvironment {
            environment["BACKUP_PASSWORD"] = currentPassword
        } else {
            arguments.append(currentPassword)
        }
        run(JobRequest(kind: .encryptionOff,
                       arguments: arguments,
                       environment: environment,
                       secrets: [currentPassword],
                       udid: device.id,
                       deviceName: device.name,
                       startStatus: "Turning off backup encryption on \(device.name)...",
                       startStage: Model.passcodeReminder,
                       logHeader: "Turning off backup encryption on \(device.name)"))
    }

    /// Changes the backup password stored on the selected device.
    func changeEncryptionPassword(old oldPassword: String, new newPassword: String) {
        if let problem = encryptionProblem() { status = problem; return }
        guard let device = chosenDevice else { return }
        if oldPassword.isEmpty || newPassword.isEmpty {
            failBeforeStart(kind: .changePassword, status: "The backup password was not changed.",
                            hint: "Enter the current password and a new one.")
            return
        }
        if oldPassword == newPassword {
            failBeforeStart(kind: .changePassword, status: "The backup password was not changed.",
                            hint: "The new password is the same as the current one.")
            return
        }
        if details[device.id]?.backupEncryption == false {
            failBeforeStart(kind: .changePassword, status: "The backup password was not changed.",
                            hint: "Backup encryption is not on for this phone, so there is no password to change.")
            return
        }
        var arguments = ["-u", device.id, "changepw"]
        var environment: [String: String] = [:]
        if passwordsViaEnvironment {
            environment["BACKUP_PASSWORD"] = oldPassword
            environment["BACKUP_PASSWORD_NEW"] = newPassword
        } else {
            arguments += [oldPassword, newPassword]
        }
        run(JobRequest(kind: .changePassword,
                       arguments: arguments,
                       environment: environment,
                       secrets: [oldPassword, newPassword],
                       udid: device.id,
                       deviceName: device.name,
                       startStatus: "Changing the backup password on \(device.name)...",
                       startStage: Model.passcodeReminder,
                       logHeader: "Changing the backup password on \(device.name)"))
    }

    // MARK: Cancel, dismiss, log

    /// Asks the running tool to stop. It gets an interrupt signal first, which lets it tell the phone and
    /// tidy up; if it is still running half a minute later it is stopped the hard way.
    func cancel() {
        guard busy, !cancelling, let process = current, process.isRunning else { return }
        cancelRequested = true
        cancelling = true
        status = "Stopping..."
        stage = "Waiting for the phone to stop. This can take a moment."
        process.interrupt()
        let token = operationToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self = self, self.busy, self.operationToken == token else { return }
            guard let running = self.current, running.isRunning else { return }
            kill(running.processIdentifier, SIGKILL)
        }
    }

    /// Dismisses the result of the last job (the success / failure / cancelled banner).
    func acknowledgeOutcome() {
        if busy { return }
        outcome = .none
        errorHint = ""
        status = "Ready."
        stage = ""
        currentFile = ""
        progress = 0
        fileProgress = 0
    }

    func clearLog() {
        logLines = []
        logText = ""
    }

    /// Copies the log to the clipboard.
    func copyLog() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(logText, forType: .string)
    }

    // MARK: Running the tool

    /// Records a job that could not even be started as a failure, so the UI shows one consistent end state.
    func failBeforeStart(kind: OperationKind, status text: String, hint: String) {
        operation = kind
        outcome = .failure
        progress = 0
        fileProgress = 0
        currentFile = ""
        stage = ""
        elapsed = 0
        cancelling = false
        status = text
        errorHint = hint
    }

    /// Starts idevicebackup2 and follows it until it exits. Main queue only.
    func run(_ job: JobRequest) {
        if busy { return }
        guard let toolPath = Tools.path("idevicebackup2") else {
            failBeforeStart(kind: job.kind, status: "\(job.kind.title) could not start.",
                            hint: "idevicebackup2 is not installed. Run \"\(Model.installCommand)\" in Terminal.")
            return
        }

        operationToken += 1
        let token = operationToken
        busy = true
        operation = job.kind
        outcome = .none
        progress = 0
        fileProgress = 0
        currentFile = ""
        stage = job.startStage
        status = job.startStatus
        errorHint = ""
        elapsed = 0
        cancelling = false
        cancelRequested = false
        verdict = .unknown
        parser.reset()
        operationDeviceName = job.deviceName
        operationUDID = job.udid
        operationSecrets = job.secrets.filter { !$0.isEmpty }
        logLines = [job.logHeader]
        logText = job.logHeader

        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = job.arguments
        process.environment = Tools.environment(adding: job.environment)
        process.standardInput = FileHandle.nullDevice

        // A pseudo-terminal makes the tool flush every line as it prints it, so prompts such as
        // "enter the passcode on the device" show up straight away. A plain pipe is the fallback.
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        var outputPipe: Pipe?
        let readFD: Int32
        if openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 {
            let slaveHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
            process.standardOutput = slaveHandle
            process.standardError = slaveHandle
            readFD = masterFD
        } else {
            masterFD = -1
            slaveFD = -1
            let made = Pipe()
            process.standardOutput = made
            process.standardError = made
            outputPipe = made
            readFD = made.fileHandleForReading.fileDescriptor
        }

        do {
            try process.run()
        } catch {
            if masterFD >= 0 { close(masterFD) }
            if slaveFD >= 0 { close(slaveFD) }
            busy = false
            operationSecrets = []
            failBeforeStart(kind: job.kind, status: "\(job.kind.title) could not start.",
                            hint: "idevicebackup2 could not be started: \(error.localizedDescription)")
            return
        }
        // Our copy of the terminal's far end has to go, or reading would never see the end of the output.
        if slaveFD >= 0 { close(slaveFD) }

        current = process
        let began = Date()
        startedAt = began
        elapsedTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, self.busy, self.operationToken == token else { return }
            self.elapsed = Date().timeIntervalSince(began)
        }
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer

        let ownsDescriptor = masterFD >= 0
        // Captured by the reader below so the pipe stays open until reading is over.
        let keptPipe = outputPipe
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var pending = Data()
            var buffer = [UInt8](repeating: 0, count: 16384)
            while true {
                let count = buffer.withUnsafeMutableBytes { raw -> Int in
                    return read(readFD, raw.baseAddress, raw.count)
                }
                if count > 0 {
                    pending.append(contentsOf: buffer[0..<count])
                    let text = Model.takeText(from: &pending)
                    if !text.isEmpty {
                        DispatchQueue.main.async {
                            self?.consume(text, token: token)
                        }
                    }
                } else if count < 0 && errno == EINTR {
                    continue
                } else {
                    // 0 = end of a pipe; an error (EIO) = the tool closed the terminal by exiting.
                    break
                }
            }
            if ownsDescriptor { close(readFD) }
            process.waitUntilExit()
            let code = process.terminationStatus
            let rest = String(decoding: pending, as: UTF8.self)
            DispatchQueue.main.async {
                _ = keptPipe
                self?.finish(code: code, rest: rest, token: token)
            }
        }
    }

    /// Splits complete UTF-8 text off the front of `pending`, leaving an unfinished character (if any) for later.
    static func takeText(from pending: inout Data) -> String {
        if pending.isEmpty { return "" }
        let bytes = [UInt8](pending)
        var cut = bytes.count
        var back = 1
        while back <= 4 && back <= bytes.count {
            let byte = bytes[bytes.count - back]
            if byte & 0xC0 == 0x80 {
                // A continuation byte: keep looking for the byte that starts the character.
                back += 1
                continue
            }
            var needed = 1
            if byte & 0xE0 == 0xC0 {
                needed = 2
            } else if byte & 0xF0 == 0xE0 {
                needed = 3
            } else if byte & 0xF8 == 0xF0 {
                needed = 4
            }
            if needed > back { cut = bytes.count - back }
            break
        }
        let text = String(decoding: bytes[0..<cut], as: UTF8.self)
        pending = Data(bytes[cut...])
        return text
    }

    /// Takes a piece of tool output on the main queue.
    func consume(_ text: String, token: Int) {
        guard busy, token == operationToken else { return }
        let parsed = parser.feed(text)
        absorb(parsed)
    }

    /// Applies parsed output to the published state.
    func absorb(_ parsed: ParsedOutput) {
        var sawProgress = false
        if let value = parsed.overall {
            sawProgress = true
            if abs(value - progress) >= 0.001 { progress = value }
        }
        if let value = parsed.file {
            sawProgress = true
            if abs(value - fileProgress) >= 0.001 { fileProgress = value }
        }
        if let name = parsed.fileName, name != currentFile { currentFile = name }
        if cancelling {
            // Keep the "Stopping" text on screen.
        } else if let text = parsed.stage {
            if text != stage { stage = text }
        } else if sawProgress && (stage == Model.passcodePrompt || stage == Model.passcodeReminder) {
            stage = ""
        }

        if parsed.lines.isEmpty { return }
        for raw in parsed.lines {
            let line = redact(raw)
            let found = ToolVerdict.from(line: line)
            if found != .unknown { verdict = found }
            if !cancelling, let prompt = ErrorExplainer.prompt(forLine: line) { stage = prompt }
            logLines.append(line)
        }
        if logLines.count > 400 { logLines.removeFirst(logLines.count - 400) }
        logText = logLines.joined(separator: "\n")
    }

    /// Blanks out a password should the tool ever print one.
    func redact(_ line: String) -> String {
        var result = line
        for secret in operationSecrets where secret.count >= 4 {
            if result.contains(secret) {
                result = result.replacingOccurrences(of: secret, with: "<password>")
            }
        }
        return result
    }

    /// Called once on the main queue when the tool has exited.
    func finish(code: Int32, rest: String, token: Int) {
        guard token == operationToken else { return }
        if !rest.isEmpty { absorb(parser.feed(rest)) }
        absorb(parser.flush())

        elapsedTimer?.invalidate()
        elapsedTimer = nil
        if let began = startedAt { elapsed = Date().timeIntervalSince(began) }
        startedAt = nil
        current = nil

        let kind = operation
        let name = operationDeviceName.isEmpty ? "the phone" : operationDeviceName
        let time = Format.duration(elapsed)
        let result: OperationOutcome
        if verdict == .success {
            result = .success
        } else if cancelRequested || verdict == .aborted {
            result = .cancelled
        } else if verdict == .unknown && code == 0 {
            // No verdict line, but the tool only exits with 0 when the phone reported success.
            result = .success
        } else {
            result = .failure
        }

        var hint = ""
        var summary = ""
        switch result {
        case .success:
            progress = 1
            switch kind {
            case .backup: summary = "Backup of \(name) finished in \(time)."
            case .restore:
                summary = restoreReboot
                    ? "Restore finished in \(time). \(name) is restarting; leave it plugged in until it is back on the Home Screen."
                    : "Restore finished in \(time). Restart \(name) to finish."
            case .encryptionOn: summary = "Backup encryption is now on for \(name). Keep the password safe: without it these backups cannot be restored."
            case .encryptionOff: summary = "Backup encryption is now off for \(name)."
            case .changePassword: summary = "The backup password of \(name) was changed."
            case .none: summary = "Done."
            }
        case .cancelled:
            let where_ = cancelRequested ? "" : " on the phone"
            switch kind {
            case .backup: summary = "Backup stopped\(where_) after \(time). The unfinished backup cannot be restored; the next backup continues from it."
            case .restore: summary = "Restore stopped\(where_) after \(time). The phone may be left partly restored: run the restore again."
            default: summary = "Stopped\(where_). Nothing was changed."
            }
        case .failure, .none:
            switch kind {
            case .backup: summary = "Backup of \(name) failed after \(time)."
            case .restore: summary = "Restore onto \(name) failed after \(time)."
            case .encryptionOn: summary = "Backup encryption could not be turned on."
            case .encryptionOff: summary = "Backup encryption could not be turned off."
            case .changePassword: summary = "The backup password could not be changed."
            case .none: summary = "The job failed."
            }
            if let known = ErrorExplainer.hint(for: logLines) {
                hint = known
            } else if let last = logLines.last, logLines.count > 1 {
                hint = "The tool reported: \(last)"
            } else {
                hint = "The tool stopped without saying why (exit code \(code)). Unlock the phone, check the cable and try again."
            }
        }

        stage = ""
        currentFile = ""
        cancelling = false
        cancelRequested = false
        operationSecrets = []
        errorHint = hint
        status = summary
        outcome = result == .none ? .failure : result
        busy = false

        if kind == .restore && result == .success { password = "" }

        // The backup folder of this device has changed: forget its size so it is measured again.
        if kind == .backup {
            let wanted = operationUDID.lowercased()
            for backup in backups where backup.root == operationRoot && !backup.archived && backup.udid.lowercased() == wanted {
                backupSizes[backup.id] = nil
            }
        }

        // Bring everything that the job may have changed up to date.
        loadBackups()
        refreshDestinationInfo()
        refreshDevices(forceDetails: true)
    }
}
