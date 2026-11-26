import SwiftUI
import AppKit

// AppModel.swift
// The one ObservableObject behind the whole window: published state, device polling,
// the backup list and file actions on backups.
// Long-running jobs live in AppModelOperations.swift, short device actions in AppModelDeviceActions.swift.
//
// Threading rule used everywhere: tools and file work run on DispatchQueue.global,
// every @Published property is read and written on the main queue only.
// Every method of Model must be called on the main queue.

/// UserDefaults keys. Passwords are never stored.
enum DefaultsKey {
    static let destination = "backupDestination"
    static let forceFullBackup = "forceFullBackup"
    static let restoreSystemFiles = "restoreSystemFiles"
    static let restoreSettings = "restoreSettings"
    static let restoreReboot = "restoreReboot"
    static let restoreSkipApps = "restoreSkipApps"
    static let restoreRemoveItems = "restoreRemoveItems"
    static let restoreCopyFirst = "restoreCopyFirst"
}

final class Model: ObservableObject {

    // MARK: Devices

    /// Devices attached over USB, refreshed every 3 seconds while idle.
    @Published var devices: [Device] = []
    /// Battery, storage, encryption and Find My per UDID; refreshed about every 15 seconds.
    @Published var details: [String: DeviceDetails] = [:]
    /// UDID of the device the user picked.
    @Published var selectedDevice: String?

    // MARK: Backups

    /// Backups found in both folders, newest first.
    @Published var backups: [Backup] = []
    /// Size on disk in bytes per backup id; an entry is missing until it has been measured.
    @Published var backupSizes: [String: Int64] = [:]
    /// Id (folder path) of the backup the user picked.
    @Published var selectedBackup: String?
    /// Whether Finder's backup folder can be read (.denied means Full Disk Access is needed).
    @Published var finderAccess: FolderAccess = .unknown
    /// Sentence explaining the Full Disk Access problem, or "" when there is none.
    @Published var finderNote = ""
    /// Where new backups go. Saved in UserDefaults.
    @Published var destination: BackupDestination = .own {
        didSet {
            UserDefaults.standard.set(destination.rawValue, forKey: DefaultsKey.destination)
            refreshDestinationInfo()
        }
    }
    /// Free space on the Mac volume holding the destination folder, in bytes.
    @Published var destinationFree: Int64?
    /// Pass --full so the phone sends everything again instead of only changes. Saved in UserDefaults.
    @Published var forceFullBackup = true {
        didSet { UserDefaults.standard.set(forceFullBackup, forKey: DefaultsKey.forceFullBackup) }
    }

    // MARK: Restore options (each maps to one idevicebackup2 restore flag; all saved in UserDefaults)

    /// --system: restore system files too.
    @Published var restoreSystemFiles = true {
        didSet { UserDefaults.standard.set(restoreSystemFiles, forKey: DefaultsKey.restoreSystemFiles) }
    }
    /// --settings: replace the phone's settings with the ones in the backup.
    @Published var restoreSettings = true {
        didSet { UserDefaults.standard.set(restoreSettings, forKey: DefaultsKey.restoreSettings) }
    }
    /// When false, --no-reboot is passed and the phone does not restart afterwards.
    @Published var restoreReboot = true {
        didSet { UserDefaults.standard.set(restoreReboot, forKey: DefaultsKey.restoreReboot) }
    }
    /// --skip-apps: do not ask the phone to reinstall apps after the restore.
    @Published var restoreSkipApps = false {
        didSet { UserDefaults.standard.set(restoreSkipApps, forKey: DefaultsKey.restoreSkipApps) }
    }
    /// --remove: remove items from the phone that are not part of the backup.
    @Published var restoreRemoveItems = false {
        didSet { UserDefaults.standard.set(restoreRemoveItems, forKey: DefaultsKey.restoreRemoveItems) }
    }
    /// --copy: let the tool copy the backup folder before restoring from it (needs the space twice).
    @Published var restoreCopyFirst = false {
        didSet { UserDefaults.standard.set(restoreCopyFirst, forKey: DefaultsKey.restoreCopyFirst) }
    }
    /// Password of the selected encrypted backup, typed by the user for a restore.
    /// Kept in memory only: never logged, never shown in status text, never saved.
    @Published var password = ""

    // MARK: Long-running job (backup, restore, encryption change)

    /// True while idevicebackup2 is running.
    @Published var busy = false
    /// Which job is running, or the last one that ran.
    @Published var operation: OperationKind = .none
    /// How the last job ended; .none while one is running.
    @Published var outcome: OperationOutcome = .none
    /// Overall progress 0...1.
    @Published var progress: Double = 0
    /// Progress of the file being transferred 0...1.
    @Published var fileProgress: Double = 0
    /// Name of the file being transferred (only reported by newer tool builds), or "".
    @Published var currentFile = ""
    /// Short text about what is happening right now ("Receiving files", "Enter the passcode on the phone"), or "".
    @Published var stage = ""
    /// One-line summary for the user; the final verdict once a job has ended.
    @Published var status = "Ready."
    /// Plain-language advice after a failure ("Find My is on ..."), or "".
    @Published var errorHint = ""
    /// Seconds since the job started; stops counting when it ends.
    @Published var elapsed: TimeInterval = 0
    /// True after cancel() until the tool has actually stopped.
    @Published var cancelling = false
    /// Output of the tool (progress bars removed), newest lines last, at most 400 lines.
    @Published var logText = ""

    // MARK: Short device actions (pair, restart, shut down, recovery, archive, delete)

    /// True while a short action is running.
    @Published var actionBusy = false
    /// Result of the last short action, or what is running now; "" when there is nothing to say.
    @Published var actionMessage = ""

    // MARK: Tools

    /// True when a required tool is not installed; nothing works until it is.
    @Published var toolsMissing = false
    /// Names of the missing tools, required ones first.
    @Published var missingTools: [String] = []
    /// Version of idevicebackup2, e.g. "1.4.0"; "" when unknown.
    @Published var toolVersion = ""
    /// True when passwords can be handed to the tool through environment variables (1.4.0 and newer).
    /// When false they are passed as arguments, which other programs on this Mac can see while the tool runs.
    @Published var passwordsViaEnvironment = false

    // MARK: Folders

    let ownRoot = BackupStore.ownRoot
    let finderRoot = BackupStore.finderRoot

    static let fullDiskAccessMessage = "PhoneVault needs Full Disk Access to use Finder's backup folder. Open System Settings > Privacy & Security > Full Disk Access, turn on PhoneVault, then quit and reopen it."

    // MARK: Internal state (not for the views; internal instead of private because the extensions use it)

    var logLines: [String] = []
    var parser = OutputParser()
    var firmwareParser = FirmwareParser()

    // MARK: Installing iOS (IPSW)
    /// Full path of the IPSW file chosen for installing iOS ("" = none chosen).
    @Published var ipswPath = ""
    /// Erase the device and install (true) or update and keep its data (false).
    @Published var firmwareErase = false
    /// Download and install the newest version Apple signs instead of a chosen file.
    @Published var firmwareLatest = false
    var current: Process?
    var cancelRequested = false
    var verdict: ToolVerdict = .unknown
    var startedAt: Date?
    var elapsedTimer: Timer?
    var operationToken = 0
    var operationRoot = ""
    /// Name of the device the running job works on (for the final status sentence).
    var operationDeviceName = ""
    /// UDID of that device.
    var operationUDID = ""
    /// Passwords handed to the running job, kept only so they can be blanked out of the log.
    var operationSecrets: [String] = []
    var refreshing = false
    var refreshTick = 0
    var wantDetails = false
    var pairTried = Set<String>()
    /// Devices the polling must leave alone: the user tapped "Don't Trust" on them, or unpaired them here.
    /// Every ideviceinfo run asks a device without a pairing to pair again (the library does that by
    /// itself), which would put a new Trust prompt on its screen. They are asked again once they have
    /// been unplugged, or when the user asks for it (pair).
    var quietDevices = Set<String>()
    var pollTimer: Timer?
    var scanGeneration = 0
    var sizing = Set<String>()
    let sizeQueue = DispatchQueue(label: "local.phonevault.sizes", qos: .utility)
    var quitObserver: NSObjectProtocol?
    /// Whether PhoneVault is the frontmost app. While it is not, device polling slows down.
    var appActive = true
    var activityObservers: [NSObjectProtocol] = []

    // MARK: Start-up

    init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: DefaultsKey.destination), let saved = BackupDestination(rawValue: raw) {
            destination = saved
        }
        forceFullBackup = Model.savedBool(DefaultsKey.forceFullBackup, fallback: true)
        restoreSystemFiles = Model.savedBool(DefaultsKey.restoreSystemFiles, fallback: true)
        restoreSettings = Model.savedBool(DefaultsKey.restoreSettings, fallback: true)
        restoreReboot = Model.savedBool(DefaultsKey.restoreReboot, fallback: true)
        restoreSkipApps = Model.savedBool(DefaultsKey.restoreSkipApps, fallback: false)
        restoreRemoveItems = Model.savedBool(DefaultsKey.restoreRemoveItems, fallback: false)
        restoreCopyFirst = Model.savedBool(DefaultsKey.restoreCopyFirst, fallback: false)

        checkTools()
        loadBackups()
        refreshDestinationInfo()
        refreshDevices()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
        // Do not leave a backup tool running behind our back when the app quits.
        // The name is spelled out (it is NSApplication.willTerminateNotification) so this class does not
        // have to touch a main-actor type from its initialiser.
        // Poll less often while another app is in front (names spelled out for the same reason as below).
        for (name, active) in [("NSApplicationDidBecomeActiveNotification", true), ("NSApplicationDidResignActiveNotification", false)] {
            let token = NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                self.appActive = active
                if active { self.refreshDevices() }
            }
            activityObservers.append(token)
        }
        quitObserver = NotificationCenter.default.addObserver(forName: Notification.Name("NSApplicationWillTerminateNotification"),
                                                              object: nil, queue: .main) { [weak self] _ in
            if let p = self?.current, p.isRunning { p.interrupt() }
        }
    }

    static func savedBool(_ key: String, fallback: Bool) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil { return fallback }
        return defaults.bool(forKey: key)
    }

    // MARK: Selection helpers

    var chosenDevice: Device? { return devices.first { $0.id == selectedDevice } }
    var chosenBackup: Backup? { return backups.first { $0.id == selectedBackup } }
    /// Details of the selected device, when they have been read.
    var chosenDetails: DeviceDetails? {
        guard let id = selectedDevice else { return nil }
        return details[id]
    }

    /// Backups made from the given device, newest first (archived ones included).
    func backups(for udid: String) -> [Backup] {
        let wanted = udid.lowercased()
        return backups.filter { $0.udid.lowercased() == wanted }
    }

    /// Date of the newest backup of the given device on this Mac, or nil when there is none.
    func lastBackupDate(for udid: String) -> Date? {
        return backups(for: udid).compactMap { $0.date }.max()
    }

    // MARK: Tools

    /// Looks for the command-line tools and asks idevicebackup2 what it supports.
    func checkTools() {
        let missingRequired = Tools.required.filter { !Tools.exists($0) }
        let missingOptional = Tools.optional.filter { $0 != "irecovery" && $0 != "idevicerestore" && !Tools.exists($0) }
        missingTools = missingRequired + missingOptional
        toolsMissing = !missingRequired.isEmpty
        if toolsMissing { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let info = Tools.backupToolInfo()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.toolVersion = info.version
                self.passwordsViaEnvironment = info.passwordsViaEnvironment
            }
        }
    }

    // MARK: Devices

    /// Re-reads the list of connected devices. Does nothing while a job or action is running.
    /// - Parameter forceDetails: also re-read battery, storage, encryption and Find My now.
    func refreshDevices(forceDetails: Bool = false) {
        if forceDetails { wantDetails = true }
        if busy || actionBusy || refreshing || toolsMissing { return }
        refreshTick += 1
        // In the background, look every third tick (about every 9 seconds) unless asked to look now.
        if !appActive && !forceDetails && refreshTick % 3 != 0 { return }
        refreshing = true
        let fetchAll = wantDetails || refreshTick % 5 == 1
        wantDetails = false
        let known = Set(details.keys)
        // A trusted device whose basics were read recently is not asked again on every tick.
        var cached: [String: Device] = [:]
        if !fetchAll {
            for device in devices where device.trusted { cached[device.id] = device }
        }
        // Keep showing a declined or unpaired device as it was instead of asking it (and so prompting) again.
        var declined: [String: Device] = [:]
        for device in devices where quietDevices.contains(device.id) { declined[device.id] = device }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var found: [Device] = []
            var fresh: [String: DeviceDetails] = [:]
            for udid in DeviceQuery.listUDIDs() {
                if let kept = declined[udid] {
                    found.append(kept)
                    continue
                }
                let device = cached[udid] ?? DeviceQuery.device(udid: udid)
                found.append(device)
                if device.trusted && (fetchAll || !known.contains(udid)) {
                    fresh[udid] = DeviceQuery.details(udid: udid)
                }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.refreshing = false
                self.apply(devices: found, details: fresh)
            }
        }
    }

    private func apply(devices found: [Device], details fresh: [String: DeviceDetails]) {
        if devices != found { devices = found }

        var merged: [String: DeviceDetails] = [:]
        for device in found {
            if let value = fresh[device.id] ?? details[device.id] {
                merged[device.id] = value
            }
        }
        if merged != details { details = merged }

        if let sel = selectedDevice, !found.contains(where: { $0.id == sel }) {
            selectedDevice = nil
        }
        if selectedDevice == nil, let first = found.first {
            selectedDevice = first.id
        }
        // A device that reports "declined" is not asked again by the polling (see quietDevices).
        // Unplugging a device clears its mark because it then drops out of `found`.
        let connected = Set(found.map { $0.id })
        quietDevices = quietDevices.intersection(connected).union(found.filter { $0.trust == .denied }.map { $0.id })
        // Start pairing once for every device that is not trusted yet, so the Trust dialog appears.
        for device in found where !device.trusted && !pairTried.contains(device.id) {
            pairTried.insert(device.id)
            let udid = device.id
            DispatchQueue.global().async {
                _ = Tools.run("idevicepair", ["-u", udid, "pair"], timeout: 30)
            }
        }
        // Forget devices that were unplugged so they are paired again next time.
        pairTried = pairTried.filter { id in found.contains(where: { $0.id == id }) }
    }

    // MARK: Backups

    /// Re-reads both backup folders in the background, then measures any backup whose size is unknown.
    func loadBackups() {
        scanGeneration += 1
        let generation = scanGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scan = BackupStore.scanAll()
            DispatchQueue.main.async {
                guard let self = self, generation == self.scanGeneration else { return }
                self.apply(backups: scan.backups, finderAccess: scan.finderAccess)
            }
        }
    }

    private func apply(backups list: [Backup], finderAccess access: FolderAccess) {
        if backups != list { backups = list }
        if finderAccess != access { finderAccess = access }
        let note = access == .denied
            ? "Backups made by Finder stay hidden until PhoneVault has Full Disk Access (System Settings > Privacy & Security > Full Disk Access)."
            : ""
        if finderNote != note { finderNote = note }
        if let sel = selectedBackup, !list.contains(where: { $0.id == sel }) { selectedBackup = nil }
        // Drop sizes of backups that are gone.
        let ids = Set(list.map { $0.id })
        let kept = backupSizes.filter { entry in ids.contains(entry.key) }
        if kept.count != backupSizes.count { backupSizes = kept }
        measureBackups()
    }

    /// Measures, off the main thread, every backup that has no entry in `backupSizes` yet.
    func measureBackups() {
        let pending = backups.filter { backupSizes[$0.id] == nil && !sizing.contains($0.id) }
        if pending.isEmpty { return }
        for backup in pending { sizing.insert(backup.id) }
        sizeQueue.async { [weak self] in
            for backup in pending {
                let size = BackupStore.folderSize(backup.path)
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.sizing.remove(backup.id)
                    if self.backups.contains(where: { $0.id == backup.id }) {
                        self.backupSizes[backup.id] = size
                    }
                }
            }
        }
    }

    /// Updates `destinationFree` (and `finderAccess` when Finder's folder is the destination).
    func refreshDestinationInfo() {
        let root = BackupStore.root(for: destination)
        let checkFinder = destination == .finder
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let free = BackupStore.freeSpace(at: root)
            let access: FolderAccess? = checkFinder ? BackupStore.access(to: root) : nil
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.destinationFree = free
                if let access = access, self.finderAccess != access { self.finderAccess = access }
            }
        }
    }

    /// Folder new backups are written to.
    var destinationRoot: String { return BackupStore.root(for: destination) }

    /// Problem with the chosen destination that the user should know about before backing up, or nil.
    var destinationProblem: String? {
        if destination == .finder && finderAccess == .denied { return Model.fullDiskAccessMessage }
        return nil
    }

    // MARK: File actions on backups

    /// Opens the destination folder in Finder (creating PhoneVault's own folder if needed).
    func revealBackupsFolder() {
        if destination == .own {
            try? FileManager.default.createDirectory(atPath: ownRoot, withIntermediateDirectories: true)
        }
        let root = destinationRoot
        if FileManager.default.fileExists(atPath: root) {
            NSWorkspace.shared.open(URL(fileURLWithPath: root))
        } else {
            actionMessage = "That folder does not exist yet."
        }
    }

    /// Shows one backup folder in Finder.
    func reveal(_ backup: Backup) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: backup.path)])
    }

    /// Opens the Full Disk Access pane of System Settings.
    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Why a backup cannot be archived or deleted right now, or nil.
    func fileActionProblem(_ backup: Backup) -> String? {
        if busy { return "Wait until the current job has finished." }
        if actionBusy { return "Wait until the current action has finished." }
        if !FileManager.default.fileExists(atPath: backup.path) { return "That backup folder no longer exists." }
        return nil
    }

    /// Renames the backup folder to "<UDID>-<date>-<time>" so the next backup of that device
    /// does not update or overwrite it. Archived backups can still be restored.
    func archive(_ backup: Backup) {
        if let problem = fileActionProblem(backup) { actionMessage = problem; return }
        if backup.archived { actionMessage = "That backup is already archived."; return }
        actionBusy = true
        actionMessage = "Archiving the backup of \(backup.name)..."
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var message = "Archived. The next backup of \(backup.name) will start a new folder."
            do {
                _ = try BackupStore.archive(backup)
            } catch {
                message = "Could not archive the backup: \(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.actionBusy = false
                self.actionMessage = message
                self.loadBackups()
            }
        }
    }

    /// DESTRUCTIVE (recoverable): moves the backup folder to the Trash. Put this behind a confirmation.
    func trash(_ backup: Backup) {
        if let problem = fileActionProblem(backup) { actionMessage = problem; return }
        actionBusy = true
        actionMessage = "Moving the backup of \(backup.name) to the Trash..."
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var message = "The backup of \(backup.name) is in the Trash."
            do {
                try BackupStore.trash(backup)
            } catch {
                message = "Could not move the backup to the Trash: \(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.actionBusy = false
                self.actionMessage = message
                self.loadBackups()
                self.refreshDestinationInfo()
            }
        }
    }
}
