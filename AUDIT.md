# PhoneVault audit

Third pass over the project, done after the backend and UI were written. Still no Mac: nothing here was built with a macOS SDK, and no real iPhone or real libimobiledevice tool was involved.

Short version: no compile error was found in the project as it was handed over. Nine changes were made; they are behaviour and safety hardening plus two "doubtful construct" replacements. The backend was compiled and run for real on Linux against fake tools and passed 82 checks.

## 1. What was checked, and how

### Mechanical (a tool did the checking)

| Check | Tool | Covers | Result |
|---|---|---|---|
| Syntax of all 21 Swift files | Swift 5.10.1 compiler (Linux, from Ubuntu's `swiftlang` packages, unpacked in /tmp) and tree-sitter-swift 0.7.4 | every file | no errors, no ERROR/MISSING nodes |
| Type check of the whole project in one module, `-swift-version 5 -parse-as-library` | Swift 5.10.1 against hand-written stub modules `SwiftUI` and `AppKit` (kept outside the project) | all 21 files, about 5,500 lines: every model member a view uses (name, type, labels), optionals, `let`/`var`, exhaustive switches, duplicate file-scope names, missing imports, builder shapes | 0 errors, 0 warnings, before and after the changes |
| Real compile, link and run of the backend | Swift 5.10.1 on Linux, real Foundation | `Tools`, `Models`, `OutputParser`, `DeviceQuery`, `BackupStore`, `AppModel`, `AppModelOperations`, `AppModelDeviceActions` | built; 82 runtime checks pass (see below) |
| `bash -n build.sh` | bash | syntax only | ok |
| `Resources/Info.plist` | Python `plistlib` | well-formed, keys present | ok |
| Makefile | `make -n` against the Theos makefiles in /tmp/theos, with `uname`, `xcrun`, `xcode-select` faked to look like macOS and an empty fake SDK | file discovery, target string, flags, bundle layout, signing step, `after-all` | as NOTES.md describes; see section 4 |

What the stubs are and are not. The stub modules declare the SwiftUI and AppKit API the project uses, written from the documented macOS 13 signatures (including the old limit of ten children per `ViewBuilder` block, `CommandsBuilder` without conditionals, and `LocalizedStringKey` interpolation limited to the types Apple supports). A clean type check against them proves the project is consistent with itself and with those signatures as written down here. It does not prove Apple's SDK agrees: a wrong stub signature would hide an error. The harness was tested by injecting three errors (a wrong model member, a wrong argument count, a missing property); all three were reported.

Runtime test of the backend. The real `Model` class was run on Linux with a run loop, against fake `idevice_id`, `ideviceinfo`, `idevicepair` and `idevicebackup2` scripts placed temporarily in `/usr/local/bin` of the sandbox (removed afterwards). The fake `idevicebackup2` prints the 1.4.0 output formats, records its arguments and environment, and reacts to SIGINT. Checked this way:

- parser: 1.3.0/1.4.0 carriage-return bars, the newer four-line ANSI block, an escape sequence split across two reads, verdict lines; UTF-8 character split across two reads
- version comparison, lockdown error parsing (old and new message format), archive folder name parsing
- device list with one trusted and one "declined" device, details (battery, storage, encryption, Find My), auto-selection, tool version and password-variable detection
- backup: argument order `-u UDID --full backup DIR`, a directory with a space, progress moving, output arriving through the pseudo-terminal (`isatty` true in the child), verdict, log without progress bars, backup listed and measured afterwards
- cancel: SIGINT, tool prints "Backup Aborted.", ends as cancelled, flags cleared
- archive: folder renamed to `UDID-date-time`, still listed, still restorable
- restore from an archived folder: `-u UDID -s FOLDER --system --settings restore DIR`; password in `BACKUP_PASSWORD` only, not in arguments, log or status; refused without a password; password cleared after success
- failed restore: `ErrorCode 211 ... Find My` becomes the Find My advice
- encryption on: `-u UDID encryption on` with `BACKUP_PASSWORD_NEW`; the passcode prompt line surfaces as `stage`
- old tool route: `--password PWD` before `restore`, `changepw OLD NEW`, nothing in the environment, nothing in the log
- the path guard for Trash and Archive (nine paths, plus a forged `Backup` value)
- the polling changes in section 2 (declined device, unpair, Ask Again)

Not coverable on Linux: `FileManager.trashItem` (does not exist there; a no-op stood in), macOS pseudo-terminal end-of-file behaviour, Full Disk Access, anything visual.

One observation for honesty: the very first run of the test program crashed inside Foundation on a background thread. That run changed environment variables with `setenv` from the test's main thread while the model's background threads were reading the environment to start tools. The test was changed to use files instead; eight further runs (four full, four partial) had no crash. The app itself never calls `setenv`, so this is attributed to the test, not to the project, but it was not proven.

### Read only (no tool; judgement)

- Every Swift file was read in full for behaviour, threading and safety.
- Tool facts were re-read in the sources: option parsing of idevicebackup2 1.3.0 (`/tmp/bk130.c`, hand-written loop) and 1.4.0/master (`getopt_long`), `getenv` use, verdict and progress `printf` formats, `ideviceinfo`, `idevicepair`, `idevicediagnostics`, `ideviceenterrecovery`, `irecovery`, and `lockdownd_client_new_with_handshake` in `src/lockdown.c`.
- SwiftUI availability and signatures of the constructs the UI agent flagged (section 3).
- Main-actor isolation as newer SDKs apply it (`View`, `App`, `Commands`, `NSApplicationDelegate`), by reasoning only.
- README against Makefile and build.sh.

## 2. Changes made

Line numbers are those after the change.

### Behaviour

1. **A device that was unpaired in the app was asked to pair again three seconds later.** `Sources/AppModel.swift` 166-170, 265-279, 308-311; `Sources/AppModelDeviceActions.swift` 37, 48, 108-125.
   Verified in `src/lockdown.c`: `lockdownd_client_new_with_handshake` calls `lockdownd_pair` whenever there is no pair record, and `ideviceinfo` uses that call. So the next polling tick after Unpair started a new pairing, which puts "Trust This Computer?" back on the phone and contradicts the app's own message. Now a successfully unpaired device is shown as "Not paired with this Mac yet" and the polling leaves it alone (`quietDevices`) until it is unplugged or the user clicks Ask Again. `runAction` got an optional `finished:` hook that runs on the main queue for this.

2. **Same treatment for a device where the user tapped Don't Trust.** Same lines. A device whose state is "declined" is queried once and then left alone until unplugged or Ask Again (and Ask Again only resumes polling if the answer was not "declined" again). Whether iOS really shows a new prompt on every request after a refusal could not be confirmed (many reports say the refusal sticks until the cable is replugged, in which case the old code was merely wasteful). The change is safe either way.

3. **Copy that named buttons which do not exist.** `Sources/AppModelDeviceActions.swift` 93, 96, 127; `Sources/OutputParser.swift` 141; `README.md` 55. Messages said "press Pair again" / "Use Pair"; the UI calls it "Ask Again" (device page) and "Ask the Device to Trust This Mac" (Device menu). The pending-trust message no longer asks for a second click, because the polling picks the device up by itself.

4. **Trust page promised automatic checking in cases where there is none now.** `Sources/Views/DeviceDetailView.swift` 271-277, 295. For a declined or unpaired device the footnote now says to click Ask Again or replug.

### Safety

5. **Trash and Archive now refuse any path that is not a folder directly inside one of the two backup folders.** `Sources/BackupStore.swift` 141-158 (`isBackupFolder`, `refusal`), 167-169, 190-192. Before, `BackupStore.trash` moved whatever `backup.path` said. In practice paths only come from the folder scan, so this was not reachable, but the rule "only ever a backup folder" is now enforced at the last step instead of assumed. Hidden names, `.`/`..`, nested paths, the roots themselves and `..` escapes are refused (tested).

6. **Archive built the new folder name from text inside the backup's Info.plist.** `Sources/BackupStore.swift` 170-179. The target was `root + "/" + backup.udid + "-" + stamp`, and `udid` comes from the "Target Identifier" key of a file inside the backup. A crafted or damaged Info.plist containing `/` or `..` could have moved the folder somewhere else. The name is now the folder's own name plus the stamp, in the same parent. For a normal backup the result is identical. Existing targets are still never overwritten.

### Doubtful constructs replaced

7. **`body` with a leading `let` and an explicit `return`.** `Sources/Views/Components.swift` 176-178 (`CopyButton.tip`), 276-278 (`CapacityBar.clamped`). Legal, but it switches the result builder off for that body and was on the UI agent's own risk list. Both values are now private computed properties and the bodies are ordinary builder bodies.

8. **`NSApplication.willTerminateNotification` referenced from the model's initialiser.** `Sources/AppModel.swift` 200-202. `NSApplication` is a main-actor type and `Model` is not isolated; with a new compiler and SDK this can produce an isolation diagnostic. The notification name is now written as `Notification.Name("NSApplicationWillTerminateNotification")`, which is the same value.

### Documentation

9. `README.md` 55: first-start step 2 rewritten (see 3), with the new "left alone until Ask Again or replug" rule.

Nothing was renamed. No file was added to `Sources/`. `NOTES.md` and `UI_NOTES.md` were left as written; where they differ from the above, this file is newer (`UI_NOTES.md` section 5 item 6 no longer applies; `NOTES.md` does not mention `quietDevices` or the `finished:` parameter of `runAction`).

## 3. The constructs the UI agent flagged

All of these type-check against the stubs; the verdict below is from knowledge of the real API.

| Construct | Verdict |
|---|---|
| `confirmationDialog(_:isPresented:titleVisibility:presenting:actions:message:)` with two trailing closures | Correct form for macOS 12+. Left. |
| `@ObservedObject` in a `Commands` struct; menu content in separate `View` structs | Compiles. The item views observe the model themselves, which is the reliable way to keep menu items live. Left. |
| `CommandGroup(replacing: .newItem) { }` | Standard idiom. Left. |
| `.keyboardShortcut(.delete, modifiers: .command)` | `KeyEquivalent.delete` exists. Left. |
| `Picker` with `String?` selection, `.tag(String?.none)` / `.tag(String?.some(id))`, `Section` inside | Tags match the selection type exactly. `Section` is a view, so it compiles; how the menu draws the section titles on each macOS version is unverified. Left. |
| One-parameter `.onChange(of:)` | Exists on macOS 13; deprecated from 14 but, with a deployment target of 13, not even a warning. Left. |
| `.background(.bar)`, `.buttonStyle(.link)`, `.navigationSubtitle`, `navigationSplitViewColumnWidth(min:ideal:max:)` | All exist on macOS 13. Left. |
| `@NSApplicationDelegateAdaptor` with `@main` | Correct. Left. |
| `body` with `let` + `return` | Replaced (change 7). |
| `Int(version.split(separator: ".").first ?? "")` | Compiled by the real compiler (standard library only). Left. |
| More than ten children in one builder block | None: the stub enforces the limit of ten. |

## 4. Build system

- **Makefile.** `find Sources -type f -name '*.swift' | sort` picks up `Sources/Views/*.swift` and nothing else (`UI_NOTES.md` is not passed to the compiler). The dry run produced one `swiftc -c` call with all 21 files, `-swift-version 5 -parse-as-library -target arm64-apple-macosx13.0`, a clang link with `-framework AppKit -framework SwiftUI` and no UIKit, `codesign --force --sign -` on the binary, resources copied by rsync, then the `after-all` rule placing `Info.plist` in `Contents/` and removing the copy in `Contents/Resources/`. `install-app` checks the binary and Info.plist exist before touching `/Applications`. No change needed.
- **Command Line Tools only.** Theos looks for SDKs in `$(xcode-select -p)/Platforms/MacOSX.platform/Developer/SDKs` and `$THEOS/sdks`. The first does not exist without Xcode, so the symlink in the README is required. Confirmed in `targets/_common/darwin_head.mk`.
- **build.sh.** Recursive, null-separated file list; every path quoted; works with the bash 3.2 that macOS ships (no `mapfile`, no associative arrays); SDK from `xcrun --sdk macosx --show-sdk-path`; bundle layout `Contents/{MacOS,Resources,Info.plist,PkgInfo}`; ad-hoc signature. No change needed.
- **README** matches both.

Not verifiable here: that Theos' Swift helper tools build on the user's Mac, and that its clang link step finds the Swift runtime. If Theos gives trouble, `./build.sh` avoids both.

## 5. Safety review (read, plus the runtime checks above)

- Restore can only start from `RestoreConfirmSheet.confirm()`. Toolbar, Device menu and the card button all go through `WindowState.requestRestore`, which opens the sheet only when `restoreProblem()` is nil; the sheet re-checks, needs the tick box, and `Model.startRestore()` checks once more. No path skips the pre-checks.
- Restart, shut down, recovery mode, unpair, move to Trash and stopping a restore only ever set `ui.confirmation`; the single dialog performs them. Turning encryption off is confirmed by its sheet. Quitting during a job is confirmed by `AppDelegate`.
- Tools are started with `Process` and argument arrays only. There is no shell, no `-c`, no AppleScript.
- Passwords: environment route when the tool supports it; inherited `BACKUP_PASSWORD*` variables are stripped from every tool's environment; arguments are never logged; nothing is written to UserDefaults.
- All published state is changed on the main queue; reader threads hand text over with `DispatchQueue.main.async`. The polling timer cannot overlap itself (`refreshing`) and does nothing while a job or action runs.

## 6. Suspected, not confirmed

1. **Stub fidelity.** The largest unknown. If Apple's signature differs from what was written into the stubs, the first build will say so.
2. **Newer compiler diagnostics.** The user's compiler is newer than 5.10 and the SDK marks more types as main-actor. In Swift 5 mode these are normally warnings. `Model`, `WindowState`, `Look`, `Confirmation` are deliberately not isolated and call nothing main-actor-only after change 8.
3. **`forceFullBackup` defaults to true** (`Sources/AppModel.swift` 58). Every backup then passes `--full` and copies everything again unless the user turns "Copy everything again" off. The README reads as if incremental were the norm. This looks like a product decision, so it was left; changing the default to `false` is a one-word edit.
4. **Pseudo-terminal on macOS.** The code path ran on Linux. On macOS the end of output is expected as `read` returning 0 or an error; both are handled. If the last lines of output were ever lost, the exit status still decides the outcome.
5. **`destination = saved` inside `Model.init`.** Whether `didSet` fires there for a property with a wrapper differs between explanations; either way the effect is one harmless extra `refreshDestinationInfo()`.
6. **Restore from an archived folder** passes the folder name as the source identifier. The tool accepts any name; whether every iOS version does was not testable.
7. **Unpair then Ask Again.** After Ask Again the polling resumes, so if the user then taps Don't Trust the device is asked once more before it goes quiet.
8. Everything in `UI_NOTES.md` section 6 (row selection inside `List` sections, log auto-scroll, strip height at the minimum window size, Return/Escape in sheets) needs eyes on a real Mac.
9. `FileManager.trashItem` was not exercised.

## 7. If the first build fails

Work through the first error only; later ones are often consequences.

| Compiler says | Where | Fix |
|---|---|---|
| `cannot find 'openpty' in scope` (or `kill`, `SIGKILL`) | `AppModelOperations.swift` | Add `import Darwin` under the existing imports. |
| `main actor-isolated ... cannot be referenced / called from a nonisolated context` | names a property or function | If it names something in `Model`, `WindowState`, `Look` or `Confirmation`: put `@MainActor` on that class, enum or extension. If it points into the `DispatchQueue.main.asyncAfter` closure of `CopyButton` (`Components.swift`): replace the closure body's wrapper with `Task { @MainActor in try? await Task.sleep(nanoseconds: 1_500_000_000); copied = false }`. |
| `ambiguous use of 'confirmationDialog'` or `extra trailing closure passed in call` | `RootView.swift`, `Dialogs` | Write the closures with labels: `actions: { item in ... }, message: { item in ... })`. |
| `the compiler is unable to type-check this expression in reasonable time` | names a line | Move the expression on that line into a `let name: String = ...` above the view code (or into a small computed property, as was done in `Components.swift`). |
| `extra argument in call` on a view with many children | a `VStack`/`Card`/`Menu` block | More than ten children with an old SDK: wrap half of them in `Group { ... }`. |
| `type 'ShapeStyle' has no member '...'` | a `.foregroundStyle(.x)` | Write `Color.x` instead. |
| `generic parameter 'SelectionValue' could not be inferred` | a `Picker` or `List` | Make the tag types explicit: `.tag(String?.some(id))` for the two restore pickers, `.tag(SidebarItem.device(id))` in the sidebar. |
| `cannot convert value of type 'Section<...>'` or a complaint about `Section` inside the backup `Picker` | `RestorePanel.swift`, `RestoreBackupChooser` | Delete the two `Section("...") { }` wrappers, keep the `ForEach` blocks, put a `Divider()` between them. |
| `'onChange(of:perform:)' was deprecated` | several | Warning only. To silence: `{ value in` becomes `{ _, value in`, and `{ _ in` becomes `{ _, _ in` (needs macOS 14 as minimum, so better left alone). |
| `invalid redeclaration of '...'` | names a type | Two files declare the same name; rename the one in `Sources/Views/` and its uses. None was found. |

| Build tool says | Fix |
|---|---|
| Theos: `You do not have any SDKs` | `ln -s /Library/Developer/CommandLineTools/SDKs/MacOSX*.*.sdk "$THEOS/sdks/"` (README). If that pattern matches nothing, link `MacOSX.sdk` under a versioned name, for example `MacOSX27.0.sdk`. |
| Theos: failure while "Building Swift support tools", or link errors such as `library not found for -lswiftCore` / undefined `_swift_...` symbols | Use `./build.sh`. |
| Theos: `ldid: command not found` | The Makefile sets `TARGET_CODESIGN = codesign`; make sure nothing in the environment overrides it. |
| `codesign: resource fork, Finder information, or similar detritus not allowed` | `xattr -cr` on the built `.app`, then sign again. |
| build.sh: `the Swift compiler was not found` | `xcode-select --install`. |
| App opens but shows the install screen although the tools are installed | They are outside `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin`, `/usr/bin`: add the folder to `Tools.dirs` in `Sources/Tools.swift`. |
