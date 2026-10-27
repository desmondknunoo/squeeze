import SwiftUI
import AppKit
import AppKit

/// Sidebar-style settings window (General / Appearance), matching the app's
/// card design language. Simple/Advanced here switches the main window mode.
struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var selection = "general"

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 190)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 560)
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let logo = NSImage(named: "AppIcon") {
                    Image(nsImage: logo)
                        .resizable()
                        .frame(width: 26, height: 26)
                        .cornerRadius(7)
                }
                Text("Squeeze")
                    .font(.headline)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            sidebarItem(id: "general", label: "General", icon: "gearshape")
            sidebarItem(id: "appearance", label: "Appearance", icon: "paintpalette")
            Spacer()
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    func sidebarItem(id: String, label: String, icon: String) -> some View {
        Button(action: { selection = id }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                Text(label)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selection == id ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    var detail: some View {
        ScrollView {
            if selection == "general" {
                generalDetail
            } else {
                appearanceDetail
            }
        }
    }

    // MARK: - General

    var generalDetail: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Default Interface")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Choose which interface to open by default when launching Squeeze.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 10) {
                interfaceCard(simple: true)
                interfaceCard(simple: false)
            }
            behaviorCard
            aboutCard
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func interfaceCard(simple: Bool) -> some View {
        let active = settings.simpleMode == simple
        return Button(action: { settings.simpleMode = simple }) {
            HStack(spacing: 10) {
                Image(systemName: simple ? "rectangle" : "slider.horizontal.3")
                    .font(.title2)
                    .foregroundColor(active ? .white : .secondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(simple ? "Simple" : "Advanced")
                        .fontWeight(.semibold)
                        .foregroundColor(active ? .white : .primary)
                    Text(simple ? "Cleaner, easier workflow" : "More options and control")
                        .font(.caption)
                        .foregroundColor(active ? .white.opacity(0.85) : .secondary)
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(active ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }

    var behaviorCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Behavior")
                .font(.headline)
            Text("Other settings to improve your experience.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            settingsCard(VStack(spacing: 0) {
                behaviorRow(icon: "terminal",
                            title: "Check ffmpeg on launch",
                            caption: "Automatically verify that ffmpeg is installed and ready to use.",
                            isOn: $settings.checkFFmpegOnLaunch)
                Divider().padding(.leading, 40)
                behaviorRow(icon: "chart.bar",
                            title: "Show compression estimates",
                            caption: "Display estimated file size before compressing.",
                            isOn: $settings.showEstimates)
            })
        }
    }

    func behaviorRow(icon: String, title: String, caption: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.separatorColor).opacity(0.5))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(caption).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .tint(Color.accentColor)
                .labelsHidden()
        }
        .padding(12)
    }

    var aboutCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("About")
                .font(.headline)
            settingsCard(HStack {
                Image(systemName: "info.circle")
                    .font(.title2)
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Squeeze").fontWeight(.medium)
                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Check for Updates…") {
                    if let url = URL(string: "https://github.com/desmondknunoo/squeeze/releases") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12))
        }
    }

    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    // MARK: - Appearance

    var appearanceDetail: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Appearance")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Choose how Squeeze looks on your Mac.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            settingsCard(VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Appearance").fontWeight(.medium)
                        Text("Follow your system or choose a specific appearance.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $settings.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Theme Color").fontWeight(.medium)
                        Text("Choose the accent color used across Squeeze.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(ThemeAccent.allCases) { theme in
                            ZStack {
                                Circle()
                                    .fill(theme.color)
                                    .frame(width: 26, height: 26)
                                if settings.accent == theme {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .onTapGesture { settings.accent = theme }
                        }
                    }
                }
            }
            .padding(14))
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func settingsCard<Content: View>(_ content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
}
