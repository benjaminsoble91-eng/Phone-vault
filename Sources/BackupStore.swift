import Foundation

// BackupStore.swift
// Finds backups on disk and does the file work around them (sizes, archiving, moving to the Trash).
// No UI and no shared state: call these from a background queue.
//
// Layout used by idevicebackup2 (and by Finder): DIRECTORY/<UDID>/{Info.plist, Manifest.plist, Status.plist, ...}
// With --source NAME the tool reads DIRECTORY/NAME instead, which is how archived backups are restored.

enum BackupStore {
    static let ownRoot = NSHomeDirectory() + "/PhoneVault Backups"
    static let finderRoot = NSHomeDirectory() + "/Library/Application Support/MobileSync/Backup"

    static func root(for destination: BackupDestination) -> String {
        switch destination {
        case .own: return ownRoot
        case .finder: return finderRoot
        }
    }

    /// Checks whether a folder can be listed. A permission error means Full Disk Access is missing.
    static func access(to folder: String) -> FolderAccess {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: folder)
            return .ok
        } catch {
            let ns = error as NSError
            if ns.domain == NSCocoaErrorDomain && (ns.code == NSFileReadNoSuchFileError || ns.code == NSFileNoSuchFileError) {
                return .missing
            }
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
               underlying.domain == NSPOSIXErrorDomain, underlying.code == Int(ENOENT) {
                return .missing
            }
            return .denied
        }
    }

    /// Makes sure a destination folder exists and can be used. Returns what we ended up with.
    static func prepare(_ folder: String) -> FolderAccess {
        let first = access(to: folder)
        if first != .missing { return first }
        do {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        } catch {
            return .denied
        }
        return access(to: folder)
    }

    static func readPlist(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return nil }
        return obj as? [String: Any]
    }

    /// Lists the backups inside one root folder.
    static func scan(root: String, label: String) -> [Backup] {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: root) else { return [] }
        var list: [Backup] = []
        for item in items {
            if item.hasPrefix(".") { continue }
            let dir = root + "/" + item
            guard let info = readPlist(dir + "/Info.plist") else { continue }
            var encrypted = false
            if let manifest = readPlist(dir + "/Manifest.plist") {
                encrypted = (manifest["IsEncrypted"] as? Bool) ?? false
            }
            var complete = false
            if let status = readPlist(dir + "/Status.plist") {
                complete = ((status["SnapshotState"] as? String) ?? "") == "finished"
            }
            let target = (info["Target Identifier"] as? String) ?? ""
            let udid = target.isEmpty ? baseUDID(ofFolder: item) : target
            let type = (info["Product Type"] as? String) ?? ""
            list.append(Backup(id: dir,
                               udid: udid,
                               folder: item,
                               root: root,
                               name: (info["Device Name"] as? String) ?? "Unknown device",
                               model: friendlyModel(type),
                               version: (info["Product Version"] as? String) ?? "?",
                               date: info["Last Backup Date"] as? Date,
                               encrypted: encrypted,
                               source: label,
                               serial: (info["Serial Number"] as? String) ?? "",
                               archived: item.lowercased() != udid.lowercased(),
                               complete: complete))
        }
        return list
    }

    /// Lists the backups in both folders, newest first, and reports whether Finder's folder is readable.
    static func scanAll() -> (backups: [Backup], finderAccess: FolderAccess) {
        var list = scan(root: ownRoot, label: "PhoneVault")
        let finder = access(to: finderRoot)
        if finder == .ok {
            list += scan(root: finderRoot, label: "Finder")
        }
        list.sort { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
        return (list, finder)
    }

    /// "00008030-001A2B3C4D5E6F-20261125-101500" -> "00008030-001A2B3C4D5E6F"
    static func baseUDID(ofFolder folder: String) -> String {
        if let range = folder.range(of: "-[0-9]{8}-[0-9]{6}$", options: .regularExpression) {
            return String(folder[folder.startIndex..<range.lowerBound])
        }
        return folder
    }

    /// Space the folder takes on disk, in bytes. Slow for big backups.
    static func folderSize(_ path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: nil) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in walker {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isRegularFile != true { continue }
            if let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Free space on the volume that holds `path` (or its nearest existing parent), in bytes.
    static func freeSpace(at path: String) -> Int64? {
        var probe = path
        while !FileManager.default.fileExists(atPath: probe) && probe != "/" && !probe.isEmpty {
            probe = (probe as NSString).deletingLastPathComponent
        }
        if probe.isEmpty { probe = "/" }
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: probe),
              let free = attrs[.systemFreeSize] as? NSNumber else { return nil }
        return free.int64Value
    }

    /// True when `path` is a folder directly inside PhoneVault's or Finder's backup folder.
    /// Archive and Trash refuse anything else, whatever a Backup value claims.
    static func isBackupFolder(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let name = url.lastPathComponent
        if name.isEmpty || name == "." || name == ".." || name.hasPrefix(".") { return false }
        let parent = url.deletingLastPathComponent().path
        for root in [ownRoot, finderRoot] {
            if parent == URL(fileURLWithPath: root).standardizedFileURL.path { return true }
        }
        return false
    }

    static func refusal(_ text: String) -> NSError {
        return NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                       userInfo: [NSLocalizedDescriptionKey: text])
    }

    /// Renames a live backup folder to "<UDID>-<yyyyMMdd>-<HHmmss>" (the scheme Finder uses for archived backups),
    /// so the next backup of the same device starts a fresh folder instead of updating this one.
    /// Returns the new path.
    static func archive(_ backup: Backup) throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        guard isBackupFolder(backup.path) else {
            throw refusal("That folder is not inside a backup folder PhoneVault manages.")
        }
        // The new name is built from the folder's own name (the UDID for a live backup), never from
        // text read out of the backup's Info.plist, and the folder stays where it is.
        let parent = (backup.path as NSString).deletingLastPathComponent
        let base = (backup.path as NSString).lastPathComponent
        let stamp = formatter.string(from: backup.date ?? Date())
        var target = parent + "/" + base + "-" + stamp
        if FileManager.default.fileExists(atPath: target) {
            // Same second as an existing archive: fall back to the current time.
            target = parent + "/" + base + "-" + formatter.string(from: Date())
        }
        if FileManager.default.fileExists(atPath: target) {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError,
                          userInfo: [NSLocalizedDescriptionKey: "An archive with that name already exists."])
        }
        try FileManager.default.moveItem(atPath: backup.path, toPath: target)
        return target
    }

    /// Moves a backup folder to the Trash.
    static func trash(_ backup: Backup) throws {
        guard isBackupFolder(backup.path) else {
            throw refusal("That folder is not inside a backup folder PhoneVault manages.")
        }
        try FileManager.default.trashItem(at: URL(fileURLWithPath: backup.path), resultingItemURL: nil)
    }
}
