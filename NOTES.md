# PhoneVault notes (backend agent)

Status: complete. Nothing in this project has been compiled or run (no Mac and no Swift compiler were available).

## 0. Things the UI must know first

- The observable class is called **`Model`** (not `AppModel`), declared in `Sources/AppModel.swift` as `final class Model: ObservableObject`. Create it once with `@StateObject private var model = Model()` in the `@main` App and pass it down with `.environmentObject(model)` / `@EnvironmentObject var model: Model`.
- `Model.init()` starts everything itself (tool check, backup scan, 3 second device polling). The UI does not need to start timers.
- Every method of `Model` must be called on the main thread (button actions are fine). All `@Published` values change on the main thread only.
- Value types are in `Sources/Models.swift`: `Device`, `DeviceDetails`, `Backup`, `TrustState`, `BackupDestination`, `FolderAccess`, `OperationKind`, `OperationOutcome`, and the helpers `Format.bytes(_:)`, `Format.duration(_:)`, `Format.date(_:)`, `friendlyModel(_:)`.
- Backend files (do not edit): `Tools.swift`, `Models.swift`, `OutputParser.swift`, `DeviceQuery.swift`, `BackupStore.swift`, `AppModel.swift`, `AppModelOperations.swift`, `AppModelDeviceActions.swift`.
- Names already taken at file scope (do not redeclare in views): `Model`, `Device`, `DeviceDetails`, `Backup`, `TrustState`, `BackupDestination`, `FolderAccess`, `OperationKind`, `OperationOutcome`, `ToolResult`, `DataBox`, `Tools`, `DeviceQuery`, `BackupStore`, `OutputParser`, `ParsedOutput`, `ErrorExplainer`, `ToolVerdict`, `JobRequest`, `DefaultsKey`, `Format`, `modelNames`, `friendlyModel`.
- The app must not be sandboxed (it runs Homebrew tools and reads `~/Library`). No entitlements file is used.

## 1. Model API

"CONFIRM" = put this behind a confirmation dialog. Methods that cannot run right now do not crash: they set `status` / `actionMessage` to the reason and return.

### Published state: devices

| Member | Type | Meaning |
|---|---|---|
| `devices` | `[Device]` | Devices attached over USB, refreshed every 3 s while idle. |
| `details` | `[String: DeviceDetails]` | Battery, storage, encryption flag, Find My per UDID (about every 15 s). |
| `selectedDevice` | `String?` | UDID of the picked device. Auto-set to the first device; bind a `List(selection:)` or Picker to it. |

`Device` fields: `id` (UDID), `udid`, `name`, `model` (friendly), `version`, `trusted: Bool`, `trust: TrustState` (`.explanation` gives a sentence), `productType`, `deviceClass`, `serial`, `build`.
`DeviceDetails` fields (all optional): `batteryPercent: Int?`, `charging: Bool?`, `storageTotal: Int64?`, `storageFree: Int64?`, `storageUsed: Int64?` (computed), `backupEncryption: Bool?`, `findMy: Bool?`.

### Published state: backups

| Member | Type | Meaning |
|---|---|---|
| `backups` | `[Backup]` | Backups in both folders, newest first. |
| `backupSizes` | `[String: Int64]` | Bytes on disk per `backup.id`; entry missing while still being measured (show "Calculating..."). |
| `selectedBackup` | `String?` | `backup.id` of the picked backup (the one Restore uses). |
| `finderAccess` | `FolderAccess` | `.denied` = Full Disk Access needed for Finder's folder. |
| `finderNote` | `String` | Sentence about hidden Finder backups, or "". |
| `destination` | `BackupDestination` | `.own` / `.finder`; saved. Bind a Picker (`BackupDestination.allCases`, `.title`). |
| `destinationFree` | `Int64?` | Free bytes on the Mac volume of the destination. |
| `forceFullBackup` | `Bool` | Passes `--full`. Saved. |

`Backup` fields: `id` (= `path`), `udid`, `folder`, `root`, `name`, `model`, `version`, `date: Date?`, `encrypted`, `source` ("PhoneVault"/"Finder"), `serial`, `archived`, `complete` (false = unfinished, cannot be restored).

### Published state: restore options (all saved)

`restoreSystemFiles` (default true), `restoreSettings` (true), `restoreReboot` (true), `restoreSkipApps` (false), `restoreRemoveItems` (false), `restoreCopyFirst` (false): all `Bool`, bind to Toggles.
`password: String` : password of the selected encrypted backup for a restore. Bind a `SecureField`. Memory only. The model clears it after a successful restore.

### Published state: the running job

| Member | Type | Meaning |
|---|---|---|
| `busy` | `Bool` | True while backup / restore / encryption change runs. |
| `operation` | `OperationKind` | Current or last job (`.title` for display). |
| `outcome` | `OperationOutcome` | `.none` while running or before any job; then `.success` / `.failure` / `.cancelled`. |
| `progress` | `Double` | Overall 0...1. |
| `fileProgress` | `Double` | Current file 0...1. |
| `currentFile` | `String` | File name (newer tool builds only) or "". |
| `stage` | `String` | Short live text ("Receiving files", "Enter the passcode on the phone to continue.") or "". |
| `status` | `String` | One-line summary; the final verdict after a job ends. |
| `errorHint` | `String` | Plain-language advice after a failure, or "". |
| `elapsed` | `TimeInterval` | Seconds since the job started; frozen when it ends. Show with `model.elapsedText`. |
| `cancelling` | `Bool` | True after `cancel()` until the tool has stopped. |
| `logText` | `String` | Tool output (max 400 lines). Never contains a password. |

### Published state: short actions and tools

| Member | Type | Meaning |
|---|---|---|
| `actionBusy` | `Bool` | True while pair / unpair / restart / shut down / recovery / archive / delete runs. |
| `actionMessage` | `String` | Result of the last short action, or "". |
| `toolsMissing` | `Bool` | A required tool is missing: show the install screen instead of the main UI. |
| `missingTools` | `[String]` | Names of missing tools (required first, then optional). |
| `toolVersion` | `String` | idevicebackup2 version or "". |
| `passwordsViaEnvironment` | `Bool` | False = old tool, passwords must go on the command line (show `passwordNote`). |

### Read-only helpers (computed, cheap, safe to call from `body`)

| Member | Meaning |
|---|---|
| `chosenDevice: Device?` | The selected device. |
| `chosenBackup: Backup?` | The selected backup. |
| `chosenDetails: DeviceDetails?` | Details of the selected device. |
| `backups(for udid: String) -> [Backup]` | Backups of one device. |
| `lastBackupDate(for udid: String) -> Date?` | Newest backup date of one device. |
| `destinationRoot: String` | Folder new backups go to. |
| `destinationProblem: String?` | Full Disk Access message when Finder's folder is chosen but unreadable. |
| `ownRoot`, `finderRoot: String` | The two folders. |
| `Model.fullDiskAccessMessage` (static) | The Full Disk Access instructions. |
| `Model.installCommand` (static) | `brew install libimobiledevice` (plus note text in `Model.installHelp`). |
| `elapsedText: String` | `elapsed` as "1:05". |
| `canStart: Bool` | True when no job and no action is running and the tools exist. |
| `backupProblem() -> String?` | Why Back Up cannot start now (nil = OK). Disable the button and show the text. |
| `backupWarning() -> String?` | Non-blocking note before a backup (Mac may not have enough free space), or nil. |
| `restoreProblem() -> String?` | Why Restore cannot start now: no device, no backup, unfinished backup, backup iOS newer than phone, missing password, Find My on, etc. (nil = OK). |
| `restoreWarnings() -> [String]` | Non-blocking warnings to list in the restore confirmation (replaces data, different phone, Find My unknown...). Never empty when a restore is possible. |
| `encryptionProblem() -> String?` | Why encryption cannot be changed now (nil = OK). |
| `fileActionProblem(_ backup: Backup) -> String?` | Why a backup cannot be archived / deleted now. |
| `deviceActionProblem(_ device: Device, tool: String) -> String?` | Why a device action cannot run (tool = "idevicepair", "idevicediagnostics", "ideviceenterrecovery"). |
| `toolAvailable(_ name: String) -> Bool` | Whether an optional tool is installed (e.g. hide Restart when "idevicediagnostics" is missing). |
| `Model.compareVersions(_ a: String, _ b: String) -> Int?` (static) | -1 / 0 / 1 for version strings, nil when not comparable. |
| `passwordNote: String` | Warning to show next to password fields when `passwordsViaEnvironment` is false, else "". |

### Actions

| Method | Confirm? | What it does |
|---|---|---|
| `checkTools()` | no | Re-check installed tools ("Check again" button on the install screen). |
| `refreshDevices(forceDetails: Bool = false)` | no | Re-read devices now; `true` also re-reads battery/storage/encryption. |
| `loadBackups()` | no | Re-scan both backup folders. |
| `refreshDestinationInfo()` | no | Re-read free space / folder access. |
| `startBackup()` | no | Back up the selected device to `destination`. |
| `startRestore()` | **CONFIRM** (strong: replaces data on the phone; list `restoreWarnings()`) | Restore `selectedBackup` onto `selectedDevice` with the restore options and `password`. |
| `cancel()` | optional (a cancelled restore can leave the phone half restored: confirm when `operation == .restore`) | Stop the running job. |
| `enableEncryption(password: String)` | no (ask for the password twice in the UI) | Turn on backup encryption on the selected device. |
| `disableEncryption(password: String)` | **CONFIRM** | Turn it off (needs the current password). |
| `changeEncryptionPassword(old: String, new: String)` | no | Change the device's backup password. |
| `acknowledgeOutcome()` | no | Dismiss the success/failure/cancelled banner (sets `outcome = .none`, clears `errorHint`, status "Ready."). |
| `clearLog()` | no | Empty `logText`. |
| `copyLog()` | no | Copy `logText` to the clipboard. |
| `pair(_ device: Device)` | no | Start pairing (shows Trust on the phone). |
| `unpair(_ device: Device)` | **CONFIRM** | Remove the pairing with this Mac. |
| `restart(_ device: Device)` | **CONFIRM** | Restart the phone. |
| `shutDown(_ device: Device)` | **CONFIRM** | Power the phone off. |
| `enterRecovery(_ device: Device)` | **CONFIRM** (strong: phone shows the cable screen and disappears from the list until it leaves recovery) | Put the phone in recovery mode. |
| `exitRecovery()` | no | Tell a phone that is in recovery mode to boot normally (needs `irecovery`; check `toolAvailable("irecovery")`). |
| `revealBackupsFolder()` | no | Open the destination folder in Finder. |
| `reveal(_ backup: Backup)` | no | Show a backup in Finder. |
| `openFullDiskAccessSettings()` | no | Open the Full Disk Access settings pane. |
| `archive(_ backup: Backup)` | no | Rename the folder so the next backup does not overwrite it. |
| `trash(_ backup: Backup)` | **CONFIRM** | Move the backup to the Trash. |

### End states of a job

When `busy` goes false: `outcome` is `.success`, `.failure` or `.cancelled`; `status` holds the verdict sentence; `errorHint` holds advice (failure only); `progress` is 1 on success. Suggested UI: green / red / grey banner keyed on `outcome`, with a Dismiss button calling `acknowledgeOutcome()`.

### Behaviour details worth knowing in the UI

- `status` is also where a refused start is reported (for example `startBackup()` while `backupProblem()` is not nil). Disable buttons with the `...Problem()` helpers and show their text.
- A job that cannot even start (folder not writable, empty password, tool missing) ends as `outcome == .failure` with `errorHint` set, without `busy` ever becoming true.
- `stage` starts as "Keep the phone unlocked. If it asks for its passcode, enter it." for backups and encryption changes and is cleared when progress arrives.
- While `busy` or `actionBusy` is true the device list is not refreshed. It refreshes right after.
- `selectedDevice` is set to the first device automatically and reset to nil when that device is unplugged. `selectedBackup` is never set automatically.
- `enableEncryption` / `disableEncryption` / `changeEncryptionPassword` work on `selectedDevice`.
- After a successful restore `password` is emptied.
- `cancel()` sends SIGINT (the tool stops cleanly); 30 seconds later, if still running, SIGKILL.

## 2. Verified tool facts

Read from the clones in /tmp (libimobiledevice tags 1.3.0 and 1.4.0 plus master, libirecovery master). "Both" below means 1.3.0 and 1.4.0; master agrees unless noted.

### idevicebackup2

- Usage: `idevicebackup2 [OPTIONS] CMD [CMDOPTIONS] DIRECTORY`. The backup lives in `DIRECTORY/<UDID>/`; with `-s NAME` / `--source NAME` the tool uses `DIRECTORY/NAME/` and sends NAME to the phone as the source identifier. That is how archived folders and other devices' backups are restored.
- Options present in both: `-u/--udid`, `-s/--source`, `-i/--interactive`, `-n/--network`, `-d`, `-h`, `-v/--version`; for backup `--full`; for restore `--system`, `--settings`, `--no-reboot`, `--reboot`, `--copy`, `--remove`, `--skip-apps`, `--password PWD`.
- 1.3.0 walks argv by hand (any order). 1.4.0 and master use `getopt_long`, so PhoneVault puts every option before the command word.
- Encryption: `encryption on|off [PWD]`, `changepw [OLD NEW]`. No DIRECTORY needed.
- Passwords from the environment: `BACKUP_PASSWORD` (current / restore password) and `BACKUP_PASSWORD_NEW` (new password) exist in **1.4.0 and master only**. 1.3.0 has no `getenv` at all. So the brief's "if confirmed in both versions" is NOT met for 1.3.0: the app detects support by looking for `BACKUP_PASSWORD` in `--help` (`Tools.backupToolInfo()`), uses the environment when found, and otherwise falls back to arguments and shows `passwordNote`.
- The tool never prints a password (for restore and unback it prints only "Backup password: Yes" or "No"). The app additionally blanks any password of 4 or more characters out of log lines.
- Final lines, same in all three versions: "Backup Successful.", "Backup Aborted.", "Backup Failed (Error Code N).", "Restore Successful.", "Restore Aborted.", "Restore Failed (Error Code N).", "Backup encryption has been enabled successfully.", "...disabled successfully.", "Backup encryption password has been changed successfully.", "Could not enable backup encryption." (and disable / change), "Operation Failed.", "Operation Aborted.". Device-side errors appear as "ErrorCode N: text".
- Exit status: 0 only when the phone reported ErrorCode 0; otherwise -1 (255) or the negated device error code. Early exits (no device, bad folder) return -1.
- SIGINT, SIGTERM and SIGQUIT are all caught and only set a quit flag ("we need to exit cleanly on running backups and restores or we cause havok"). Hence SIGINT for cancel and SIGKILL as the last resort.
- Progress output: 1.3.0 and 1.4.0 redraw one line with `\r` (`[====   ]  42%`, per-transfer bars followed by ` (1.2 MB/7.0 MB)`, overall bar followed by ` Finished`). Master draws a four-line block with ANSI escapes (`Backup [###...] 42%`, `Receiving name`, `[==>  ] 17.3%   a / b`, `Status text`). `OutputParser` handles both.
- Master only: prints "*** Waiting for passcode to be entered on the device ***" during a backup. All versions print "Please confirm ... by entering the passcode on the device." for encryption changes when the phone asks for it.
- Whether a backup will be encrypted is the lockdown value `com.apple.mobile.backup` / `WillEncrypt` (the tool reads the same key).
- stdout is not flushed after every line when it is a pipe, so the app runs the tool on a pseudo-terminal (`openpty`), falling back to a pipe.

### Other tools (same syntax in 1.3.0, 1.4.0 and master)

- `idevice_id -l`: one UDID per line (some builds append a connection type after a space).
- `ideviceinfo -u UDID -x [-q DOMAIN]`: XML plist on stdout. Exit status is 0 even when the query returned nothing. On a lockdown failure it prints `ERROR: Could not connect to lockdownd: <text> (<code>)` to stderr. Domains used: default, `com.apple.mobile.battery`, `com.apple.disk_usage`, `com.apple.mobile.backup`, `com.apple.fmip` (all in the tool's list of known domains).
- lockdown error codes (lockdown.h): -17 password protected (locked), -18 user denied pairing, -19 pairing dialog response pending, -21 invalid host ID, -2 invalid configuration.
- `lockdownd_client_new_with_handshake` starts pairing by itself when there is no pair record, so simply polling `ideviceinfo` makes the Trust dialog appear.
- `idevicepair -u UDID pair|unpair`: prints `SUCCESS: Paired with device UDID` / `SUCCESS: Unpaired with device UDID`, or `ERROR: ...` (trust dialog pending, passcode set, user denied).
- `idevicediagnostics -u UDID restart|shutdown`: prints "Restarting device." / "Shutting down device." on success.
- `ideviceenterrecovery UDID` (positional UDID, no `-u`): prints "Device is successfully switching to recovery mode." on success.
- `irecovery -n` (libirecovery): sets auto-boot true, saves and reboots; tries to connect for about 6 seconds and prints `ERROR: ...` when no recovery-mode device is found. Exit status is 0 even if a later step failed.

### Theos (read from /tmp/theos/makefiles)

- `TARGET := macosx:clang:latest:13.0` = platform, compiler, SDK version, deployment version (target.mk and darwin_head.mk: when the second field is `clang` the next two are SDK and deployment target).
- targets/Darwin/macosx.mk sets the bundle type to hierarchical: binary in `Contents/MacOS`, resources in `Contents/Resources`, Info.plist in `Contents`.
- instance/rules.mk: Swift files are compiled per architecture with `swiftc -c ... -output-file-map`; `-parse-as-library` is added automatically when no source is called `main.swift` (needed for `@main`); `-swift-version` defaults to 5; sources in sub-folders are supported.
- The built bundle is `$(THEOS_OBJ_DIR)/PhoneVault.app` = `.theos/obj/macosx/debug/PhoneVault.app` (debug) or `.theos/obj/macosx/PhoneVault.app` (FINALPACKAGE=1). Checked with a dry run of the Makefile against the Theos makefiles with the platform forced to Darwin.
- instance/shared/bundle.mk copies `Resources/` into `Contents/Resources` and moves `Info.plist` up to `Contents`, but the test for the move is evaluated when the makefile is parsed, before the copy. On a clean build the move is skipped. The Makefile's `after-all::` rule copies Info.plist into `Contents` itself.
- macosx.mk leaves `TARGET_CODESIGN` empty, and darwin_head.mk then substitutes `ldid`. The Makefile sets `TARGET_CODESIGN = codesign` with `--force --sign -` so no ldid is needed.
- Theos' own `install` and `package` targets are package based (pkg) and need a `control` file; they are not used. The project's target is `install-app`.

## 3. Open risks

Nothing was compiled or run. In rough order of likelihood:

1. **Swift compile errors.** All files were re-read for types, labels and braces, but without a compiler. Most exposed spots: `openpty` / `read` / `close` / `kill` called from Swift through Foundation in `AppModelOperations.swift` (if `openpty` is not found, add `import Darwin` at the top of that file), and anything in the views against the model API.
2. **Theos with a macOS Swift app is unconfirmed.** The makefiles support it on paper (verified by reading and by a dry run), but: Theos' Swift helper tools (`vendor/swift-support`) were an empty submodule in the clone and could not be read; the link step uses clang with `-L<toolchain>/lib/swift/macosx -L/usr/lib/swift` and relies on Swift auto-linking, which could not be tried; signing the freshly linked binary with `codesign` under its temporary `.unsigned` name could not be tried. With only the Command Line Tools, Theos finds no SDK until one is linked into `$THEOS/sdks` (see README). `build.sh` is the fallback.
3. **Restoring from an archived folder** passes the folder name ("UDID-date-time") as the source identifier. The tool supports any name, and Finder uses the same naming, but whether every iOS version accepts it was not tested. Fallback for the user: rename the folder back to the plain UDID.
4. **Restore pre-checks are limited.** The password pre-check only tests that a password was typed (verifying it needs the backup keybag and PBKDF2, which was left out to stay inside Foundation). The Find My check depends on the phone answering the `com.apple.fmip` query; when it does not, a warning is shown instead of a block.
5. **Device details may be missing on recent iOS.** Battery, storage and Find My come from lockdown domains that newer iOS versions may restrict; every field is optional and the UI must cope with nil.
6. **Progress in 1.3.0 / 1.4.0** is coarse: `progress` only moves when the phone reports overall progress, `fileProgress` follows the current transfer batch.
7. **libimobiledevice 1.3.0** forces passwords onto the command line (visible in `ps` while the tool runs). The app warns through `passwordNote`. If version detection fails on a newer tool, the argument fallback is used there too, and a password starting with "-" would then be misread as an option.
8. **Model names**: the table ends at the iPhone 17 family and older iPads; newer devices show their raw identifier (for example "iPhone19,1").
9. **Full Disk Access with ad-hoc signing**: macOS may forget the grant after each rebuild.
10. **Homebrew may ship a tool newer than the versions read here**; unknown output lines simply go to the log, and the exit status decides success when no verdict line is recognised.
