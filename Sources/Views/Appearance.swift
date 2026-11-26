import SwiftUI
import AppKit

// Appearance.swift
// Dark / Light / Match System, chosen in the View menu and remembered between launches.
// Dark is the default.

enum AppAppearance: String, CaseIterable, Identifiable {
    case dark
    case light
    case system

    static let defaultsKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "Match System"
        }
    }

    static func from(_ raw: String?) -> AppAppearance {
        return AppAppearance(rawValue: raw ?? "") ?? .dark
    }

    static var saved: AppAppearance {
        return from(UserDefaults.standard.string(forKey: defaultsKey))
    }

    /// Applies to the whole app: window, title bar, sheets, menus and alerts.
    @MainActor
    func apply() {
        switch self {
        case .dark:
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        case .light:
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .system:
            NSApplication.shared.appearance = nil
        }
    }
}

/// Keeps the app's appearance in step with the saved choice.
struct AppearanceSync: ViewModifier {
    @AppStorage(AppAppearance.defaultsKey) private var raw: String = AppAppearance.dark.rawValue

    func body(content: Content) -> some View {
        content
            .onAppear { AppAppearance.from(raw).apply() }
            .onChange(of: raw) { value in
                AppAppearance.from(value).apply()
            }
    }
}

/// The Appearance submenu in the View menu.
struct AppearanceMenuItems: View {
    @AppStorage(AppAppearance.defaultsKey) private var raw: String = AppAppearance.dark.rawValue

    var body: some View {
        Picker("Appearance", selection: $raw) {
            ForEach(AppAppearance.allCases) { item in
                Text(item.title).tag(item.rawValue)
            }
        }
    }
}
