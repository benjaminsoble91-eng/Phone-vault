# PhoneVault UI notes (UI agent)

Nothing in these files has been compiled, run or previewed: there is no Swift compiler or macOS on the
machine they were written on. Every model reference was checked by text search against
`AppModel.swift`, `AppModelOperations.swift`, `AppModelDeviceActions.swift` and `Models.swift` as they
were at the end of the work. Section 5 lists the places most likely to need a fix on first build.

## 1. Files

| File | What it holds |
|---|---|
| `Sources/PhoneVaultApp.swift` | `@main struct PhoneVaultApp: App` (one `WindowGroup`, `Model` and `WindowState` as `@StateObject`, both injected with `.environmentObject`), and `AppDelegate` (asks before quitting while a job runs; app stays open when the window is closed). |
| `Views/WindowState.swift` | View-side state shared by window, sheets and menus: `SidebarItem`, `EncryptionTask`, `Confirmation` (wording + execution of every confirmed action), `WindowState` (selection, open sheet, pending confirmation, which device the job belongs to, `requestBackup` / `requestRestore` / `requestStop` / `refreshAll`). |
| `Views/RootView.swift` | `RootView` (install screen or `NavigationSplitView`), `SelectionSync` (sidebar selection <-> `selectedDevice` / `selectedBackup`, password wiping), `Dialogs` (the one `confirmationDialog` and the two sheets), `DetailView` (page router, toolbar, activity strip). |
| `Views/SidebarView.swift` | Sidebar: Devices, Backups in PhoneVault Folder, Backups in Finder's Folder; rows, state mark, context menus, the Full Disk Access notice. |
| `Views/DeviceDetailView.swift` | Device page: header with copyable serial / UDID / model identifier, Device Actions menu, battery / storage / Find My tiles, the "not trusted yet" card. |
| `Views/BackupCard.swift` | "Back Up" card: last backup, destination picker with path and free space, encryption status with Manage menu, full-backup toggle, Back Up Now. |
| `Views/RestorePanel.swift` | "Restore" card (used on device pages and backup pages), options, password field, inline pre-check, and `RestoreConfirmSheet`. |
| `Views/EncryptionSheet.swift` | Sheet for turn on / change password / turn off backup encryption. |
| `Views/BackupDetailView.swift` | Backup page: facts, Show in Finder / Archive / Move to Trash, Restore card. |
| `Views/ActivityPanel.swift` | Bottom strip: running job (progress, elapsed, Stop), end state (finished / failed / stopped + advice, Dismiss), short-action messages, refused-start message, expandable log. |
| `Views/EmptyStates.swift` | Install screen (tools missing), no device connected, nothing selected, recovery-mode help. |
| `Views/Components.swift` | `Look` (wording / symbol helpers), `Card`, `CardBackground`, `InfoRow`, `CopyableValue`, `CopyButton`, `Notice`, `Pill`, `CapacityBar`, `MeterTile`, `CommandBox`. |
| `Views/Commands.swift` | Menu bar: Device menu and Backups menu. |

File-scope names added by the UI (do not reuse in backend files): `PhoneVaultApp`, `AppDelegate`,
`WindowState`, `SidebarItem`, `EncryptionTask`, `Confirmation`, `RootView`, `SelectionSync`, `Dialogs`,
`DetailView`, `SidebarView`, `SidebarHint`, `DeviceRow`, `DeviceRowMenu`, `DeviceStateMark`,
`BackupRow`, `BackupRowTitle`, `BackupRowMenu`, `FinderAccessNotice`, `DeviceDetailView`,
`DeviceHeader`, `DeviceIdentifiers`, `IdentifierLine`, `DeviceActionsMenu`, `DeviceMeters`,
`BatteryTile`, `StorageTile`, `FindMyTile`, `TrustCard`, `StepLine`, `BackupCard`, `LastBackupLine`,
`DestinationRows`, `EncryptionRow`, `BackupStartRow`, `RestoreContext`, `RestorePanel`,
`RestoreBackupChooser`, `ChosenBackupSummary`, `RestoreDeviceChooser`, `RestorePasswordRow`,
`RestoreOptions`, `OptionToggle`, `RestoreStartRow`, `RestoreConfirmSheet`, `RestoreConfirmHeader`,
`RestoreConfirmSummary`, `RestoreWarningList`, `EncryptionSheet`, `EncryptionSheetHeader`,
`BackupDetailView`, `BackupHeader`, `BackupPills`, `BackupFactsCard`, `BackupFileActionsCard`,
`ActivityPanel`, `JobWording`, `RunningJobView`, `JobProgressBar`, `CurrentFileLine`,
`FinishedJobView`, `ActionMessageLine`, `RefusalLine`, `LogToggle`, `LogView`, `EmptyStateLayout`,
`ToolsMissingView`, `NoDeviceView`, `RecoveryHelp`, `NothingSelectedView`, `Look`, `Card`,
`CardBackground`, `InfoRow`, `CopyableValue`, `CopyButton`, `NoticeKind`, `Notice`, `Pill`,
`CapacityBar`, `MeterTile`, `CommandBox`, `PhoneVaultCommands`, `DeviceMenuItems`,
`DeviceMenuActions`, `BackupMenuItems`.

## 2. How it fits together

- Sidebar selection is `WindowState.selection: SidebarItem?` (`.device(udid)` or `.backup(id)`).
  `SelectionSync` copies it into `model.selectedDevice` or `model.selectedBackup`. Both model selections
  can be set at once, which is what a restore needs: the device page picks the backup with a Picker
  bound to `$model.selectedBackup`; the backup page picks the device with a Picker bound to
  `$model.selectedDevice`.
- The last selected row is saved in UserDefaults under `sidebarSelection` and restored once within
  20 seconds of launch, when that device or backup shows up. Other saved view state: `showLog`,
  `showRestoreOptions` (`@AppStorage`). No password is ever saved.
- An archived backup changes its folder, hence its id. `WindowState.reconcile` follows it by matching
  UDID, root folder and date, so the page stays open after Archive.
- Confirmations. One `confirmationDialog` in `Dialogs` serves restart, shut down, recovery mode,
  unpair, move to Trash and stopping a restore (`Confirmation`). Restore has its own sheet
  (`RestoreConfirmSheet`): it lists `model.restoreWarnings()`, shows backup and target, and needs a
  tick box before the red Restore button works. Turning encryption off is confirmed by
  `EncryptionSheet` itself (consequence text, current password, red "Turn Off Encryption" button);
  there is no second dialog on top of it. Quitting while a job runs is confirmed by an `NSAlert` in
  `AppDelegate`.
- Both sheets remember which device (and backup) they were opened for. If the model's selection
  changes underneath them (device unplugged, so the model selects another one), they refuse to
  continue instead of acting on the other device.
- Passwords: `SecureField` only. The restore password is `model.password`; the views empty it when
  the selected backup changes and when a restore ends in any way (the model itself only empties it
  after a success). Encryption passwords live in `@State` of the sheet and are emptied before the
  model method is called and again in `onDisappear`.

## 3. Model members used, by file

`PhoneVaultApp.swift`: `Model()`, `busy`, `operation`.

`WindowState.swift`: `checkTools()`, `refreshDevices(forceDetails:)`, `loadBackups()`,
`refreshDestinationInfo()`, `backupProblem()`, `startBackup()`, `restoreProblem()`, `selectedDevice`,
`busy`, `cancelling`, `operation`, `cancel()`, `toolAvailable(_:)`, `backupSizes`, `restart(_:)`,
`shutDown(_:)`, `enterRecovery(_:)`, `unpair(_:)`, `trash(_:)`; `Format.date`, `Format.bytes`;
`Device.id/name`, `Backup.id/udid/root/date/name`.

`RootView.swift`: `toolsMissing`, `devices`, `backups`, `selectedDevice` (read/write),
`selectedBackup` (read/write), `busy`, `password` (write ""), `operation`, `chosenDevice`,
`backupProblem()`, `restoreProblem()`, `canStart`.

`SidebarView.swift`: `devices`, `backups`, `backupSizes`, `busy`, `finderAccess`, `finderNote`,
`Model.fullDiskAccessMessage`, `openFullDiskAccessSettings()`, `loadBackups()`, `reveal(_:)`,
`archive(_:)`, `fileActionProblem(_:)`; `Device.id/name/model/version/trusted/trust.explanation/deviceClass/productType/serial`;
`Backup.id/name/model/version/date/encrypted/archived/complete/source`.

`DeviceDetailView.swift`: `details`, `deviceActionProblem(_:tool:)`, `toolAvailable(_:)`, `pair(_:)`,
`refreshDevices(forceDetails:)`; `Device.build/serial/productType/...`;
`DeviceDetails.batteryPercent/charging/storageTotal/storageFree/storageUsed/findMy`; `Format.bytes`.

`BackupCard.swift`: `backups(for:)`, `backupSizes`, `destination` (binding), `destinationFree`,
`destinationRoot`, `destinationProblem`, `revealBackupsFolder()`, `openFullDiskAccessSettings()`,
`details[...].backupEncryption`, `encryptionProblem()`, `busy`, `selectedDevice` (write),
`forceFullBackup` (binding), `backupWarning()`, `backupProblem()`, `startBackup()`;
`BackupDestination.allCases/title`.

`RestorePanel.swift`: `chosenBackup`, `chosenDevice`, `backups`, `backups(for:)`, `devices`,
`backupSizes`, `selectedBackup` (binding), `selectedDevice` (binding), `password` (binding),
`passwordNote`, `restoreSystemFiles`, `restoreSettings`, `restoreReboot`, `restoreSkipApps`,
`restoreRemoveItems`, `restoreCopyFirst` (bindings), `restoreProblem()`, `restoreWarnings()`,
`startRestore()`, `busy`.

`EncryptionSheet.swift`: `chosenDevice`, `selectedDevice`, `encryptionProblem()`, `passwordNote`,
`enableEncryption(password:)`, `disableEncryption(password:)`, `changeEncryptionPassword(old:new:)`.

`BackupDetailView.swift`: `backupSizes`, `fileActionProblem(_:)`, `reveal(_:)`, `archive(_:)`;
`Backup.path/serial/udid/...`.

`ActivityPanel.swift`: `busy`, `outcome`, `operation`, `progress`, `fileProgress`, `currentFile`,
`stage`, `status`, `errorHint`, `elapsed`, `elapsedText`, `cancelling`, `logText`, `toolVersion`,
`actionBusy`, `actionMessage` (read, and written "" by the hide button), `acknowledgeOutcome()`,
`copyLog()`, `clearLog()`.

`EmptyStates.swift`: `missingTools`, `Model.installHelp`, `Model.installCommand`, `checkTools()`,
`refreshDevices(forceDetails:)`, `canStart`, `backups`, `toolAvailable(_:)`, `exitRecovery()`.

`Commands.swift`: `chosenDevice`, `canStart`, `busy`, `cancelling`, `deviceActionProblem(_:tool:)`,
`exitRecovery()`, `pair(_:)`, `backups`, `fileActionProblem(_:)`, `revealBackupsFolder()`,
`loadBackups()`, `reveal(_:)`, `archive(_:)`.

Not used: `lastBackupDate(for:)`, `chosenDetails`, `ownRoot`, `finderRoot`, `passwordsViaEnvironment`
(covered by `passwordNote`), `measureBackups()`.

## 4. Gaps and assumptions about the model

1. **Which device a job runs on is not published.** The model keeps `operationDeviceName` as an
   internal, unpublished property. The views record `selectedDevice` and its name at the moment
   `busy` turns true (`SelectionSync`), and use that for the "Working…" mark in the sidebar and the
   "Backing up “name”" heading. If the selection could change between the start call and the next view
   update this would be wrong; it cannot with the current model. A published `jobDeviceID` /
   `jobDeviceName` on the model would be cleaner.
2. **Which device a short action runs on is not published either**, so short actions (restart,
   pairing...) do not mark a row as busy; their text appears in the activity strip.
3. **No way to clear `actionMessage` through a method.** The hide button writes
   `model.actionMessage = ""` directly (it is a public `@Published var`).
4. **Refused starts.** The model reports them through `status` only. The activity strip shows
   `status` when no job is running or finished and it is neither empty nor exactly `"Ready."`; that
   literal is copied from the model. Its Dismiss button calls `acknowledgeOutcome()`.
5. **`backupWarning()`** exists in `AppModelOperations.swift` but is not in NOTES.md. `BackupCard`
   uses it. If it is removed, delete the three lines that call it in `BackupStartRow`.
6. **`backup.source`** is compared with the string `"Finder"` to split the sidebar into the two
   folders and to name the folder ("PhoneVault folder" / "Finder's folder").
7. **Password not verified before a restore.** `restoreProblem()` only checks that something was
   typed, so a wrong password shows up as a failed restore, not as an inline message.
8. **Wording.** `TrustState.explanation`, `restoreProblem()` and `restoreWarnings()` say "phone" and
   "iOS" even for an iPad; the views show those strings unchanged. View-written text uses
   "iPhone" / "iPad" / "iPod touch" and "iPadOS" for iPads on version 13 or later (`Look`).
9. **Exit Recovery Mode** is offered on the no-device page and in the Device menu, not on a device
   page (a device in recovery mode is not in the list). When `irecovery` is missing the page shows
   `brew install libirecovery`; that command is written in the view (the model has the same text
   inside `exitRecovery()`'s message).
10. **Trash wording.** The confirmation says the backup can be taken back out of the Trash until it
    is emptied. It does not promise Finder's "Put Back", which may not be offered for items trashed
    with `FileManager.trashItem`.
11. **Battery and storage are drawn with a custom bar (`CapacityBar`)**, not SwiftUI's `Gauge`,
    to avoid any doubt about gauge styles and label handling without a compiler.
12. **Encryption consequence text** ("leaves out saved passwords, Wi-Fi settings, Health data and
    call history"; "the only way to remove a lost password is to reset all settings") is written in
    the views from Apple's public description of encrypted backups; it does not come from the model.

## 5. Compile risks (most likely first)

1. `Dialogs` in `RootView.swift`: `.confirmationDialog(_:isPresented:titleVisibility:presenting:actions:message:)`
   written with two trailing closures. If the compiler complains, label them `actions:` and `message:`.
2. `PhoneVaultCommands`: `@ObservedObject` properties inside a `Commands` struct, an empty
   `CommandGroup(replacing: .newItem) { }`, and `.keyboardShortcut(.delete, modifiers: .command)`.
   If menu items do not enable/disable live, that is this spot too.
3. `Picker` with optional selection (`$model.selectedBackup`, `$model.selectedDevice`) using
   `.tag(String?.none)` / `.tag(String?.some(id))`, and `Section` inside a `Picker`
   (`RestoreBackupChooser`). If `Section` is rejected there, replace the two sections with a `Divider()`.
4. `.onChange(of:)` with the one-parameter closure is used throughout. It is the macOS 13 form and is
   deprecated (warning only) from macOS 14.
5. `Look.osText(version:...)`: `Int(version.split(separator: ".").first ?? "")` relies on the literal
   becoming a `Substring`.
6. `body` properties that start with a `let` and use an explicit `return` (`CopyButton`,
   `CapacityBar`): written as plain functions on purpose; they must stay single-`return`.
7. `.background(.bar)` in `ActivityPanel` (a `Material`, macOS 12+), `.buttonStyle(.link)` in
   `LastBackupLine`, `.navigationSubtitle`, `navigationSplitViewColumnWidth(min:ideal:max:)`.
8. `BackupRowMenu` receives `model` and `ui` as plain `let` parameters (not environment objects)
   because context-menu content may be built outside the environment. Sheets get both objects
   re-injected explicitly for the same reason.
9. `@NSApplicationDelegateAdaptor` together with `@main` `App`: `AppDelegate.model` is set in
   `onAppear` of the window content. Until then quitting is not guarded (nothing can be running yet).
10. SF Symbols used (all believed to exist on macOS 13; a wrong name only shows an empty image):
    archivebox, archivebox.fill, arrow.clockwise, arrow.down.doc, arrow.left.arrow.right,
    battery.0 / .25 / .50 / .75 / .100, battery.100.bolt, cable.connector, checkmark, checkmark.circle.fill,
    chevron.down, chevron.right, circle, clock.arrow.circlepath, doc.on.doc, ellipsis.circle,
    exclamationmark.triangle, exclamationmark.triangle.fill, externaldrive, folder, hand.raised,
    info.circle, internaldrive, ipad, iphone, ipodtouch, location, lock, lock.fill, lock.open,
    lock.shield, minus.circle.fill, shippingbox, sidebar.left, trash, xmark.circle.fill,
    xmark.octagon.fill.

## 6. Behaviour worth checking on a real Mac

- Closing the window does not quit (a job keeps running); clicking the Dock icon should open the
  window again. File > New Window is removed because sheets and confirmations are shared per app.
- Whether rows built by `@ViewBuilder` helpers inside `List` sections select correctly (tags are
  applied directly on the `ForEach` children).
- Whether the log follows the newest line (`ScrollViewReader.scrollTo` on every `logText` change).
- Height of the activity strip with the log open at the minimum window size (920 x 600).
- The Escape key and Return key in the two sheets (Cancel is `.cancelAction`; only the
  non-destructive confirm buttons are `.defaultAction`).
