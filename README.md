# PhoneVault

A small macOS app that finds iPhones and iPads connected by cable and makes, manages and restores their backups, for when Finder does not show the device. It is a window on top of the free [libimobiledevice](https://libimobiledevice.org) command-line tools; PhoneVault itself contains no device code.

Status: the code was written without access to a Mac. It has not been compiled or run yet. Expect to fix small things on the first build.

## Requirements

- An Apple Silicon or Intel Mac with macOS 13 or newer.
- Homebrew and the libimobiledevice tools:

  ```
  brew install libimobiledevice
  ```

  This provides `idevice_id`, `ideviceinfo`, `idevicepair`, `idevicebackup2`, `idevicediagnostics` and `ideviceenterrecovery`. PhoneVault looks for them in `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin` and `/usr/bin`.
- Optional, only for the "Exit Recovery Mode" action: `brew install libirecovery` (provides `irecovery`).
- To build: the Swift compiler, from Xcode or from the Command Line Tools (`xcode-select --install`).

Version 1.4.0 or newer of libimobiledevice is recommended. With 1.3.0 everything still works, but backup passwords have to be passed to the tool on its command line, where other programs on the Mac can see them while it runs. The app shows a note when that is the case.

## Building with Theos

```
export THEOS=~/theos        # wherever Theos is installed
cd PhoneVault
make                        # debug build
make install-app            # build, copy to /Applications, sign ad hoc, open
```

- The finished bundle is `.theos/obj/macosx/debug/PhoneVault.app`. With `make FINALPACKAGE=1` (optimised build) it is `.theos/obj/macosx/PhoneVault.app`; use `make install-app FINALPACKAGE=1` to install that one.
- `make install-app` copies the app to `/Applications`, or to `~/Applications` when `/Applications` is not writable, signs it ad hoc (`codesign --sign -`) and opens it. Do not use `make install` or `make package`; those are Theos' package targets and are not set up for this project.
- `make clean` removes the build products.
- The first Swift build with a Theos installation compiles Theos' own Swift helper tools (`vendor/swift-support`), which takes a minute and needs `swift build` to work.
- The project folder's path must not contain spaces (a Theos rule).

If Theos stops with "You do not have any SDKs": Theos looks for the macOS SDK inside Xcode (`xcode-select -p`) or in `$THEOS/sdks`. With only the Command Line Tools installed, link their SDK into Theos once:

```
ln -s /Library/Developer/CommandLineTools/SDKs/MacOSX*.*.sdk "$THEOS/sdks/"
```

## Building without Theos

```
cd PhoneVault
./build.sh
```

`build.sh` compiles all Swift files under `Sources/` with `swiftc -O -parse-as-library -swift-version 5`, creates `build/PhoneVault.app`, installs it to `/Applications` (or `~/Applications`), signs it ad hoc and opens it. `./build.sh --no-open` skips opening, `./build.sh --build-only` stops after creating `build/PhoneVault.app`.

## First start

1. Connect the iPhone with a cable and unlock it.
2. Tap **Trust** on the phone and enter its passcode. PhoneVault asks for the pairing by itself; **Ask Again** on the device page (or Device > Ask the Device to Trust This Mac) repeats the request. If you tapped Don't Trust, or unpaired the phone in PhoneVault, it is left alone until you click Ask Again or unplug it and plug it back in.
3. The phone appears with its name, model, iOS version, serial number, UDID, battery level and storage.

If macOS refuses to open the app because it is from an unidentified developer, right-click it in Finder and choose Open, or allow it in System Settings > Privacy & Security.

## Features

- Detects connected iPhones, iPads and iPod touches and shows name, model, iOS version, serial number, UDID, battery, storage, whether the phone encrypts its backups and whether Find My is on.
- Pair and unpair.
- Back up to PhoneVault's own folder (`~/PhoneVault Backups`) or to Finder's backup folder, with progress, elapsed time and Cancel.
- Lists the backups in both folders with device, iOS version, date, size on disk, encrypted or not, finished or not.
- Archive a backup (the folder is renamed so the next backup of that device starts fresh instead of updating it), move a backup to the Trash, show it in Finder.
- Backup encryption: turn on, turn off, change the password. This is a setting stored on the phone.
- Restore a backup onto the connected phone, including a backup made from a different phone, with options (system files, settings, restart afterwards, skip reinstalling apps, remove items not in the backup, copy first).
- Restart, shut down, enter recovery mode, and leave recovery mode when `irecovery` is installed.
- Plain-language explanations when something fails, and the tool's own output in a log.

Backup passwords are kept in memory only while they are needed. They are never written to the log, the status line or the app's preferences.

## Full Disk Access (only for Finder's backup folder)

Finder keeps its backups in `~/Library/Application Support/MobileSync/Backup`. macOS protects that folder: an app can only read or write it after you allow it.

1. Open System Settings > Privacy & Security > Full Disk Access.
2. Turn on PhoneVault (add it with the + button if it is not listed).
3. Quit PhoneVault and open it again.

Without this, PhoneVault still works with its own folder; backups made by Finder stay hidden and the Finder folder cannot be chosen as the destination. The app tells you when access is missing and has a button that opens the right settings page.

Because the app is signed ad hoc, macOS may treat each rebuilt copy as a new app. If Finder's folder is unreadable again after rebuilding, remove PhoneVault from the Full Disk Access list and add it again.

## Restoring: read this first

- **A restore replaces data on the phone.** Apps' data, messages, photos in the camera roll and settings are replaced by what is in the backup. Anything newer on the phone is lost. Make a fresh backup first if in doubt.
- **Find My must be off.** On the phone: Settings > your name > Find My > Find My iPhone > off. The phone refuses the restore otherwise. PhoneVault checks this when the phone reports it and blocks the restore while it is on.
- **The backup's iOS version must not be newer than the phone's.** A backup made on iOS 18 cannot be restored onto a phone running iOS 17. PhoneVault compares the versions and blocks the restore; update the phone first.
- An encrypted backup needs its password. There is no way to recover a forgotten backup password. PhoneVault only checks that a password was entered; the phone decides whether it is correct.
- Only finished backups can be restored. A backup that was cancelled or failed is shown as unfinished.
- Keep the phone connected and unlocked until it has restarted and is back on the Home Screen. Cancelling a restore part-way can leave the phone partly restored; run the restore again in that case.
- Restoring a backup from a different device works for the same kind of device (iPhone to iPhone). Some content may not carry over between different models.

## Good to know

- Recent iOS versions ask for the phone's passcode on the phone at the start of every backup. Enter it there; the backup continues by itself.
- The first backup of a phone copies everything and can take a long time. Later backups to the same folder only copy what changed, unless "full backup" is on.
- A backup made while the phone has backup encryption on is encrypted with the phone's backup password, wherever it is stored. Encrypted backups also include saved passwords, Health data and Wi-Fi settings; unencrypted ones do not.
- Recovery mode shows the "connect to computer" screen and the phone disappears from the list. To leave it, use Exit Recovery Mode (needs `irecovery`) or force-restart the phone with its buttons.

## Project layout

```
Makefile                         Theos build (macOS application, Swift)
build.sh                         fallback build with plain swiftc
Resources/Info.plist             bundle information
Sources/Tools.swift              finds and runs the command-line tools
Sources/Models.swift             Device, Backup and the other value types
Sources/OutputParser.swift       progress and error parsing of idevicebackup2 output
Sources/DeviceQuery.swift        device list and details
Sources/BackupStore.swift        backup folders: scan, size, archive, Trash
Sources/AppModel.swift           the observable model (class Model): state, polling, backup list
Sources/AppModelOperations.swift backup, restore, encryption, cancel
Sources/AppModelDeviceActions.swift  pair, unpair, restart, shut down, recovery
Sources/PhoneVaultApp.swift      app entry point
Sources/Views/                   SwiftUI views
NOTES.md                         model API and verified tool facts, for developers
```
