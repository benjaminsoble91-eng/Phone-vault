import Foundation

// DeviceQuery.swift
// Reads device information with idevice_id, ideviceinfo and idevicepair.
// Everything here blocks while a tool runs: call it from a background queue only.

enum DeviceQuery {
    /// Seconds a single query may take before it is stopped.
    static let timeout: TimeInterval = 20

    /// UDIDs of the devices attached over USB (`idevice_id -l`).
    static func listUDIDs() -> [String] {
        let listing = Tools.run("idevice_id", ["-l"], timeout: timeout).out
        var seen = Set<String>()
        var result: [String] = []
        for raw in listing.split(whereSeparator: { $0.isNewline }) {
            // Some versions append " (USB)" after the UDID.
            guard let token = raw.split(separator: " ").first else { continue }
            let udid = String(token)
            if udid.count < 20 || seen.contains(udid) { continue }
            if !udid.allSatisfy({ $0.isHexDigit || $0 == "-" }) { continue }
            seen.insert(udid)
            result.append(udid)
        }
        return result
    }

    /// Runs `ideviceinfo -x` and returns the property list as a dictionary.
    /// `domain` nil means the default domain. Returns nil when the tool failed or printed something unreadable.
    static func plist(udid: String, domain: String?) -> (values: [String: Any]?, result: ToolResult) {
        var args = ["-u", udid, "-x"]
        if let domain = domain { args += ["-q", domain] }
        let result = Tools.run("ideviceinfo", args, timeout: timeout)
        guard result.code == 0, !result.out.isEmpty else { return (nil, result) }
        let data = Data(result.out.utf8)
        guard let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = obj as? [String: Any] else { return (nil, result) }
        return (dict, result)
    }

    /// Works out why a tool could not talk to the device from its "Could not connect to lockdownd" message.
    /// The numbers are lockdownd_error_t values from libimobiledevice's lockdown.h.
    static func trustState(fromFailure text: String) -> TrustState {
        let lower = text.lowercased()
        if let code = lockdownErrorCode(in: text) {
            switch code {
            case -17: return .locked        // LOCKDOWN_E_PASSWORD_PROTECTED
            case -18: return .denied        // LOCKDOWN_E_USER_DENIED_PAIRING
            case -19: return .needsTrust    // LOCKDOWN_E_PAIRING_DIALOG_RESPONSE_PENDING
            case -21, -2: return .notPaired // LOCKDOWN_E_INVALID_HOST_ID, LOCKDOWN_E_INVALID_CONF
            default: break
            }
        }
        if lower.contains("passcode is set") || lower.contains("password protected") { return .locked }
        if lower.contains("denied") { return .denied }
        if lower.contains("trust dialog") || lower.contains("dialog response pending") { return .needsTrust }
        if lower.contains("not paired") || lower.contains("invalid hostid") { return .notPaired }
        return .unknown
    }

    /// Finds the number in "... lockdownd: Password protected (-17)" or "... lockdownd, error code -17".
    static func lockdownErrorCode(in text: String) -> Int? {
        guard text.contains("lockdownd") else { return nil }
        let patterns = ["\\((-?[0-9]+)\\)", "error code (-?[0-9]+)"]
        for pattern in patterns {
            guard let range = text.range(of: pattern, options: .regularExpression) else { continue }
            let digits = String(text[range].filter { $0.isNumber || $0 == "-" })
            if let value = Int(digits) { return value }
        }
        return nil
    }

    /// Basic facts about one device. Never fails: an unreadable device comes back untrusted.
    static func device(udid: String) -> Device {
        let query = plist(udid: udid, domain: nil)
        if let d = query.values, let name = d["DeviceName"] as? String {
            let type = (d["ProductType"] as? String) ?? ""
            return Device(id: udid,
                          name: name,
                          model: friendlyModel(type),
                          version: (d["ProductVersion"] as? String) ?? "?",
                          trusted: true,
                          trust: .trusted,
                          productType: type,
                          deviceClass: (d["DeviceClass"] as? String) ?? "",
                          serial: (d["SerialNumber"] as? String) ?? "",
                          build: (d["BuildVersion"] as? String) ?? "")
        }
        let state = trustState(fromFailure: query.result.combined)
        return Device(id: udid,
                      name: "iPhone (waiting for Trust)",
                      model: "Unknown model",
                      version: "?",
                      trusted: false,
                      trust: state)
    }

    /// Battery, storage, backup encryption and Find My for a trusted device. Four short tool runs.
    static func details(udid: String) -> DeviceDetails {
        var details = DeviceDetails()

        if let battery = plist(udid: udid, domain: "com.apple.mobile.battery").values {
            if let level = number(battery["BatteryCurrentCapacity"]) {
                details.batteryPercent = min(max(Int(level), 0), 100)
            }
            details.charging = battery["BatteryIsCharging"] as? Bool
        }

        if let disk = plist(udid: udid, domain: "com.apple.disk_usage").values {
            details.storageTotal = number(disk["TotalDiskCapacity"]) ?? number(disk["TotalDataCapacity"])
            details.storageFree = number(disk["AmountDataAvailable"]) ?? number(disk["TotalDataAvailable"])
        }

        if let backup = plist(udid: udid, domain: "com.apple.mobile.backup").values {
            // idevicebackup2 itself reads this key to decide whether a backup will be encrypted.
            details.backupEncryption = (backup["WillEncrypt"] as? Bool) ?? false
        }

        if let fmip = plist(udid: udid, domain: "com.apple.fmip").values {
            details.findMy = fmip["IsAssociated"] as? Bool
        }

        return details
    }

    /// Converts a property-list number to Int64.
    static func number(_ value: Any?) -> Int64? {
        if let n = value as? NSNumber { return n.int64Value }
        return nil
    }
}
