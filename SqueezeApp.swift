import SwiftUI

@main
struct SqueezeApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .preferredColorScheme(settings.appearance.colorScheme)
                .accentColor(settings.accent.color)
        }
        .defaultSize(width: 900, height: 640)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .preferredColorScheme(settings.appearance.colorScheme)
                .accentColor(settings.accent.color)
        }
    }
}
