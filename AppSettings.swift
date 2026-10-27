import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum ThemeAccent: String, CaseIterable, Identifiable {
    case red = "Red"
    case blue = "Blue"
    case green = "Green"
    case orange = "Orange"
    case purple = "Purple"
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: return .red
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        }
    }
}

/// Persisted user preferences. Manual UserDefaults sync (rather than @AppStorage)
/// so every change publishes through @Published and all views update live.
final class AppSettings: ObservableObject {
    @Published var simpleMode: Bool {
        didSet { UserDefaults.standard.set(simpleMode, forKey: "squeeze.simpleMode") }
    }
    @Published var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "squeeze.appearance") }
    }
    @Published var accent: ThemeAccent {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: "squeeze.accent") }
    }
    @Published var showEstimates: Bool {
        didSet { UserDefaults.standard.set(showEstimates, forKey: "squeeze.showEstimates") }
    }
    @Published var checkFFmpegOnLaunch: Bool {
        didSet { UserDefaults.standard.set(checkFFmpegOnLaunch, forKey: "squeeze.checkFFmpegOnLaunch") }
    }
    @Published var askBeforeReplace: Bool {
        didSet { UserDefaults.standard.set(askBeforeReplace, forKey: "squeeze.askBeforeReplace") }
    }

    init() {
        let defaults = UserDefaults.standard
        self.simpleMode = defaults.object(forKey: "squeeze.simpleMode") as? Bool ?? true
        self.appearance = AppearanceMode(rawValue: defaults.string(forKey: "squeeze.appearance") ?? "") ?? .system
        self.accent = ThemeAccent(rawValue: defaults.string(forKey: "squeeze.accent") ?? "") ?? .red
        self.showEstimates = defaults.object(forKey: "squeeze.showEstimates") as? Bool ?? true
        self.checkFFmpegOnLaunch = defaults.object(forKey: "squeeze.checkFFmpegOnLaunch") as? Bool ?? true
        self.askBeforeReplace = defaults.object(forKey: "squeeze.askBeforeReplace") as? Bool ?? true
    }
}
