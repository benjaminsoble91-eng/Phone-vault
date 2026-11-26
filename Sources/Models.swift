import Foundation

// Models.swift
// Plain value types shared by the model and the views, plus the model-name table.

/// Whether this Mac may talk to a connected device.
enum TrustState: String, Equatable {
    /// Paired; the tools can read the device.
    case trusted
    /// The Trust dialog is showing on the device (or has not been answered yet).
    case needsTrust
    /// The device is locked with a passcode and must be unlocked first.
    case locked
    /// The user tapped "Don't Trust".
    case denied
    /// The device does not know this Mac; pairing has to be started.
    case notPaired
    /// Anything else (device busy, booting, cable problem).
    case unknown

    /// Short sentence for the user.
    var explanation: String {
        switch self {
        case .trusted: return "Trusted"
        case .needsTrust: return "Unlock the phone and tap Trust"
        case .locked: return "Unlock the phone with its passcode"
        case .denied: return "Trust was declined on the phone. Unplug it, plug it back in and tap Trust."
        case .notPaired: return "Not paired with this Mac yet"
        case .unknown: return "Waiting for the phone to respond"
        }
    }
}

/// A connected device as listed by idevice_id, with the basics from ideviceinfo.
struct Device: Identifiable, Equatable {
    /// The UDID.
    let id: String
    var name: String
    /// Friendly model name, e.g. "iPhone 12 mini".
    var model: String
    /// iOS version, or "?" when unknown.
    var version: String
    /// True when `trust == .trusted`.
    var trusted: Bool
    var trust: TrustState = .unknown
    /// Raw identifier, e.g. "iPhone13,1".
    var productType: String = ""
    /// "iPhone", "iPad" or "iPod"; empty when unknown.
    var deviceClass: String = ""
    var serial: String = ""
    var build: String = ""

    var udid: String { return id }
}

/// Slower-changing details, refreshed every few ticks. Every field is nil when the device did not report it.
struct DeviceDetails: Equatable {
    /// 0...100.
    var batteryPercent: Int?
    var charging: Bool?
    var storageTotal: Int64?
    var storageFree: Int64?
    /// True when the device encrypts its backups with a password (lockdown key WillEncrypt).
    var backupEncryption: Bool?
    /// True when Find My is on (lockdown domain com.apple.fmip, key IsAssociated).
    var findMy: Bool?

    var storageUsed: Int64? {
        guard let total = storageTotal, let free = storageFree else { return nil }
        return max(total - free, 0)
    }
}

/// One backup folder on disk.
struct Backup: Identifiable, Equatable {
    /// Full path of the backup folder.
    let id: String
    /// UDID of the device the backup was made from.
    let udid: String
    /// Name of the backup folder inside `root`. Equal to the UDID for the live backup,
    /// "<UDID>-<yyyyMMdd>-<HHmmss>" for an archived one. This is what idevicebackup2 gets as --source.
    let folder: String
    /// The directory that contains the backup folder (the DIRECTORY argument of idevicebackup2).
    let root: String
    var name: String
    var model: String
    var version: String
    var date: Date?
    var encrypted: Bool
    /// "PhoneVault" or "Finder".
    var source: String
    var serial: String = ""
    /// True when the folder was renamed so new backups do not overwrite it.
    var archived: Bool = false
    /// True when Status.plist says the snapshot finished. The tool refuses to restore anything else.
    var complete: Bool = true

    var path: String { return id }
}

/// Where new backups are written.
enum BackupDestination: String, CaseIterable, Identifiable {
    /// ~/PhoneVault Backups
    case own
    /// ~/Library/Application Support/MobileSync/Backup (needs Full Disk Access)
    case finder

    var id: String { return rawValue }

    var title: String {
        switch self {
        case .own: return "PhoneVault folder"
        case .finder: return "Finder's folder"
        }
    }
}

/// Result of probing a folder we may not be allowed to read.
enum FolderAccess: String, Equatable {
    case unknown
    case ok
    /// The folder does not exist (yet).
    case missing
    /// macOS refused access: Full Disk Access is needed.
    case denied
}

/// The long-running job the model is doing right now.
enum OperationKind: String, Equatable {
    case none
    case backup
    case restore
    case encryptionOn
    case encryptionOff
    case changePassword
    /// Installing iOS from an IPSW with idevicerestore.
    case firmware

    var title: String {
        switch self {
        case .none: return ""
        case .backup: return "Backup"
        case .restore: return "Restore"
        case .encryptionOn: return "Turning on backup encryption"
        case .encryptionOff: return "Turning off backup encryption"
        case .changePassword: return "Changing the backup password"
        case .firmware: return "Installing iOS"
        }
    }
}

/// How the last long-running job ended.
enum OperationOutcome: String, Equatable {
    /// Nothing has run yet, or a job is running now.
    case none
    case success
    case failure
    /// Stopped by the user (in the app or on the device).
    case cancelled
}

// MARK: - Model names

let modelNames: [String: String] = [
    // iPhone
    "iPhone1,1": "iPhone", "iPhone1,2": "iPhone 3G", "iPhone2,1": "iPhone 3GS",
    "iPhone3,1": "iPhone 4", "iPhone3,2": "iPhone 4", "iPhone3,3": "iPhone 4",
    "iPhone4,1": "iPhone 4s",
    "iPhone5,1": "iPhone 5", "iPhone5,2": "iPhone 5",
    "iPhone5,3": "iPhone 5c", "iPhone5,4": "iPhone 5c",
    "iPhone6,1": "iPhone 5s", "iPhone6,2": "iPhone 5s",
    "iPhone7,2": "iPhone 6", "iPhone7,1": "iPhone 6 Plus",
    "iPhone8,1": "iPhone 6s", "iPhone8,2": "iPhone 6s Plus", "iPhone8,4": "iPhone SE",
    "iPhone9,1": "iPhone 7", "iPhone9,3": "iPhone 7", "iPhone9,2": "iPhone 7 Plus", "iPhone9,4": "iPhone 7 Plus",
    "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8", "iPhone10,2": "iPhone 8 Plus", "iPhone10,5": "iPhone 8 Plus",
    "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X",
    "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max", "iPhone11,6": "iPhone XS Max", "iPhone11,8": "iPhone XR",
    "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max",
    "iPhone12,8": "iPhone SE (2nd generation)",
    "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
    "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
    "iPhone14,6": "iPhone SE (3rd generation)",
    "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus", "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
    "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus", "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
    "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
    "iPhone17,5": "iPhone 16e",
    "iPhone18,3": "iPhone 17", "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max", "iPhone18,4": "iPhone Air",
    // iPad
    "iPad4,1": "iPad Air", "iPad4,2": "iPad Air", "iPad4,3": "iPad Air",
    "iPad5,3": "iPad Air 2", "iPad5,4": "iPad Air 2",
    "iPad11,3": "iPad Air (3rd generation)", "iPad11,4": "iPad Air (3rd generation)",
    "iPad13,1": "iPad Air (4th generation)", "iPad13,2": "iPad Air (4th generation)",
    "iPad13,16": "iPad Air (5th generation)", "iPad13,17": "iPad Air (5th generation)",
    "iPad6,11": "iPad (5th generation)", "iPad6,12": "iPad (5th generation)",
    "iPad7,5": "iPad (6th generation)", "iPad7,6": "iPad (6th generation)",
    "iPad7,11": "iPad (7th generation)", "iPad7,12": "iPad (7th generation)",
    "iPad11,6": "iPad (8th generation)", "iPad11,7": "iPad (8th generation)",
    "iPad12,1": "iPad (9th generation)", "iPad12,2": "iPad (9th generation)",
    "iPad13,18": "iPad (10th generation)", "iPad13,19": "iPad (10th generation)",
    "iPad4,4": "iPad mini 2", "iPad4,5": "iPad mini 2", "iPad4,6": "iPad mini 2",
    "iPad4,7": "iPad mini 3", "iPad4,8": "iPad mini 3", "iPad4,9": "iPad mini 3",
    "iPad5,1": "iPad mini 4", "iPad5,2": "iPad mini 4",
    "iPad11,1": "iPad mini (5th generation)", "iPad11,2": "iPad mini (5th generation)",
    "iPad14,1": "iPad mini (6th generation)", "iPad14,2": "iPad mini (6th generation)",
    "iPad6,3": "iPad Pro 9.7", "iPad6,4": "iPad Pro 9.7",
    "iPad6,7": "iPad Pro 12.9", "iPad6,8": "iPad Pro 12.9",
    "iPad7,1": "iPad Pro 12.9 (2nd generation)", "iPad7,2": "iPad Pro 12.9 (2nd generation)",
    "iPad7,3": "iPad Pro 10.5", "iPad7,4": "iPad Pro 10.5",
    "iPad8,1": "iPad Pro 11", "iPad8,2": "iPad Pro 11", "iPad8,3": "iPad Pro 11", "iPad8,4": "iPad Pro 11",
    "iPad8,5": "iPad Pro 12.9 (3rd generation)", "iPad8,6": "iPad Pro 12.9 (3rd generation)",
    "iPad8,7": "iPad Pro 12.9 (3rd generation)", "iPad8,8": "iPad Pro 12.9 (3rd generation)",
    "iPad8,9": "iPad Pro 11 (2nd generation)", "iPad8,10": "iPad Pro 11 (2nd generation)",
    "iPad8,11": "iPad Pro 12.9 (4th generation)", "iPad8,12": "iPad Pro 12.9 (4th generation)",
    "iPad13,4": "iPad Pro 11 (3rd generation)", "iPad13,5": "iPad Pro 11 (3rd generation)",
    "iPad13,6": "iPad Pro 11 (3rd generation)", "iPad13,7": "iPad Pro 11 (3rd generation)",
    "iPad13,8": "iPad Pro 12.9 (5th generation)", "iPad13,9": "iPad Pro 12.9 (5th generation)",
    "iPad13,10": "iPad Pro 12.9 (5th generation)", "iPad13,11": "iPad Pro 12.9 (5th generation)",
    "iPad14,3": "iPad Pro 11 (4th generation)", "iPad14,4": "iPad Pro 11 (4th generation)",
    "iPad14,5": "iPad Pro 12.9 (6th generation)", "iPad14,6": "iPad Pro 12.9 (6th generation)",
    // iPod touch
    "iPod7,1": "iPod touch (6th generation)", "iPod9,1": "iPod touch (7th generation)"
]

/// Friendly name for a ProductType; unknown identifiers are shown as they are.
func friendlyModel(_ type: String) -> String {
    if type.isEmpty { return "Unknown model" }
    return modelNames[type] ?? type
}

// MARK: - Formatting helpers (safe on any thread)

enum Format {
    /// "12.3 GB"
    static func bytes(_ value: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    /// "1:05" or "1:02:03"
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// "25 Nov 2026 at 10:15"
    static func date(_ date: Date) -> String {
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
}
