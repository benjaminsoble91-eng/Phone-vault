import SwiftUI
import AppKit

// Components.swift
// Small building blocks used by every page: wording helpers, cards, rows, notices, bars.

/// Wording and symbol helpers. View-side only; nothing here changes state.
enum Look {
    /// SF Symbol for a device or for the device a backup came from.
    static func symbol(deviceClass: String, model: String) -> String {
        let text = (deviceClass + " " + model).lowercased()
        if text.contains("ipad") { return "ipad" }
        if text.contains("ipod") { return "ipodtouch" }
        return "iphone"
    }

    /// "iPhone", "iPad", "iPod touch" or "device".
    static func noun(deviceClass: String, model: String) -> String {
        let text = (deviceClass + " " + model).lowercased()
        if text.contains("ipad") { return "iPad" }
        if text.contains("ipod") { return "iPod touch" }
        if text.contains("iphone") { return "iPhone" }
        return "device"
    }

    static func noun(for device: Device) -> String {
        return noun(deviceClass: device.deviceClass, model: device.model + " " + device.productType)
    }

    static func noun(for backup: Backup) -> String {
        return noun(deviceClass: "", model: backup.model)
    }

    /// "iOS 15.8.3", "iPadOS 16.7" or "iOS version unknown".
    static func osText(version: String, deviceClass: String, model: String) -> String {
        if version.isEmpty || version == "?" { return "iOS version unknown" }
        let isPad = (deviceClass + " " + model).lowercased().contains("ipad")
        let major = Int(version.split(separator: ".").first ?? "") ?? 0
        return (isPad && major >= 13 ? "iPadOS " : "iOS ") + version
    }

    static func osText(for device: Device) -> String {
        return osText(version: device.version, deviceClass: device.deviceClass, model: device.model + " " + device.productType)
    }

    static func osText(for backup: Backup) -> String {
        return osText(version: backup.version, deviceClass: "", model: backup.model)
    }

    /// "3 hours ago"
    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// "25 Nov 2026 at 10:15", or "Date unknown".
    static func dateText(_ date: Date?) -> String {
        guard let date = date else { return "Date unknown" }
        return Format.date(date)
    }

    /// "12.3 GB", or "Calculating size…" while the folder is still being measured.
    static func sizeText(_ bytes: Int64?) -> String {
        guard let bytes = bytes else { return "Calculating size…" }
        return Format.bytes(bytes)
    }

    /// "PhoneVault folder" / "Finder's folder" for a backup's `source`.
    static func folderName(for backup: Backup) -> String {
        return backup.source == "Finder" ? "Finder's folder" : "PhoneVault folder"
    }

    /// Path with the home folder written as "~".
    static func tildePath(_ path: String) -> String {
        return (path as NSString).abbreviatingWithTildeInPath
    }

    static func copy(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }
}

// MARK: - Card

/// A titled, lightly outlined box. Works on any window background in light and dark mode.
struct Card<Content: View>: View {
    private let title: String
    private let systemImage: String
    private let content: Content

    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardBackground())
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

// MARK: - Rows

/// "Label   value" with the labels right-aligned in a fixed column.
struct InfoRow<Value: View>: View {
    private let label: String
    private let value: Value

    init(_ label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .trailing)
            value
            Spacer(minLength: 0)
        }
        .font(.callout)
    }
}

/// A monospaced value the user can select, with a copy button.
struct CopyableValue: View {
    let text: String
    /// What is being copied, for the tooltip and VoiceOver ("UDID").
    let what: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text.isEmpty ? "Unknown" : text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            if !text.isEmpty {
                CopyButton(text: text, what: what)
            }
        }
    }
}

struct CopyButton: View {
    let text: String
    let what: String
    @State private var copied = false

    private var tip: String {
        return copied ? "Copied" : "Copy \(what)"
    }

    var body: some View {
        Button {
            Look.copy(text)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help(tip)
        .accessibilityLabel(Text(tip))
    }
}

// MARK: - Notices

enum NoticeKind {
    case info
    case warning
    case problem
    case success

    var symbol: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .problem: return "xmark.octagon.fill"
        case .success: return "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .info: return .secondary
        case .warning: return .orange
        case .problem: return .red
        case .success: return .green
        }
    }

    /// Read out by VoiceOver so the meaning does not depend on the colour.
    var spoken: String {
        switch self {
        case .info: return "Note"
        case .warning: return "Warning"
        case .problem: return "Problem"
        case .success: return "Done"
        }
    }
}

/// One line (or paragraph) of advice with a symbol in front.
struct Notice: View {
    let kind: NoticeKind
    let text: String

    init(_ kind: NoticeKind, _ text: String) {
        self.kind = kind
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.tint)
                .accessibilityLabel(Text(kind.spoken))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

/// Small rounded tag: symbol plus word.
struct Pill: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
    }
}

// MARK: - Bars and tiles

/// A thin filled bar, 0...1.
struct CapacityBar: View {
    let fraction: Double
    var tint: Color = .accentColor

    private var clamped: CGFloat {
        return CGFloat(min(max(fraction, 0), 1))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(geo.size.width * clamped, 6))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// A small box with a heading, one big value, an optional bar and a caption.
struct MeterTile: View {
    let title: String
    let systemImage: String
    let value: String
    let caption: String
    /// 0...1; nil hides the bar.
    let fraction: Double?
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let fraction = fraction {
                CapacityBar(fraction: fraction, tint: tint)
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .modifier(CardBackground())
        .accessibilityElement(children: .combine)
    }
}

/// A command the user can copy, in a monospaced box.
struct CommandBox: View {
    let command: String

    var body: some View {
        HStack(spacing: 10) {
            Text(command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Spacer(minLength: 8)
            CopyButton(text: command, what: "command")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

// MARK: - Icon tile and indeterminate bar

/// A rounded, tinted square holding a white symbol. Used at the top of each page.
struct IconTile: View {
    let systemImage: String
    var tint: Color = .accentColor
    var size: CGFloat = 64

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.46, weight: .regular))
                    .foregroundStyle(.white)
            )
            .shadow(color: tint.opacity(0.35), radius: 6, x: 0, y: 3)
            .accessibilityHidden(true)
    }
}

/// A slim bar with a moving highlight, for work whose total is not known yet.
/// (The system's own indeterminate bar can look like a full, finished bar.)
struct IndeterminateBar: View {
    var tint: Color = .accentColor

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { geo in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = CGFloat(t.truncatingRemainder(dividingBy: 1.6) / 1.6)
                let width = geo.size.width
                let segment = max(width * 0.28, 40)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: segment)
                        .offset(x: -segment + (width + segment) * phase)
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 6)
        .accessibilityLabel(Text("Working"))
    }
}
