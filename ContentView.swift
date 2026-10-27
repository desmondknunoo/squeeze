import SwiftUI
import AppKit
import AVFoundation
import AVKit

/// Result of a single ffprobe pass — drives codec/scale/HDR decisions.
struct ProbeInfo {
    var probed = false
    var duration: Double = 0
    var bitrate: Double = 0 // overall source bitrate, bits/sec
    var videoCodec: String?
    var audioCodec: String?
    var width: Int = 0
    var height: Int = 0
    var fps: Double = 0
    var audioSampleRate: Int = 0
    var audioChannels: Int = 0
    var isHDR = false
}

/// Gear button that opens Settings via SwiftUI's blessed API (macOS 14+).
/// The old NSApp.sendAction("showSettingsWindow:") approach silently fails
/// to reach the Settings scene, leaving the button dead.
@available(macOS 14, *)
struct SettingsGearButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(action: { openSettings() }) {
            Image(systemName: "gearshape")
        }
        .help("Settings (⌘,)")
    }
}

struct ContentView: View {    @EnvironmentObject var settings: AppSettings
    @State private var inputFile: URL?
    @State private var outputFile: URL?
    @State private var isCompressing = false
    @State private var progress: Double = 0
    @State private var selectedPreset: CompressionPreset = .balanced
    @State private var selectedEncoder: EncoderOption = .hardwareH264
    @State private var selectedResolution: ResolutionOption = .original
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @State private var ffmpegMissing = false
    @State private var outputFilename: String = ""
    @State private var showReplaceAlert = false
    @State private var inputFileSize: Int64 = 0
    @State private var outputFileSize: Int64 = 0
    @State private var statusMessage: String = ""
    @State private var elapsedTime: String = ""
    @State private var etaMessage: String = ""
    @State private var speedMessage: String = ""
    @State private var encodeFps: Int = 0
    @State private var probe: ProbeInfo = ProbeInfo()
    @State private var thumbnail: NSImage?
    @State private var player: AVPlayer?
    @State private var cropTemplate: CropTemplate = .original
    @State private var customCropW: String = ""
    @State private var customCropH: String = ""
    @State private var trimStart: String = ""
    @State private var trimEnd: String = ""
    @State private var outputFormat: OutputFormat = .mp4
    @State private var audioOnly: Bool = false
    @State private var advancedTab: AdvancedTab = .compress
    @State private var showMoreOptions = false

    enum AdvancedTab: String, CaseIterable, Identifiable {
        case compress = "Compress"
        case edit = "Edit"
        var id: String { rawValue }
    }
    // Held as reference for Cancel support
    @State private var currentProcess: Process? = nil

    enum CompressionPreset: String, CaseIterable {
        case highQuality = "High Quality"
        case balanced = "Balanced"
        case maximum = "Maximum Compression"
        case web = "Web Optimized"

        // CRF for software (libx264) path
        var crf: String {
            switch self {
            case .highQuality: return "20"
            case .balanced: return "23"
            case .maximum: return "28"
            case .web: return "30"
            }
        }

        // FIX 1: Old code used "slow" for High Quality AND Maximum.
        // "slow" is ~3-4x slower than "veryfast" for only ~5% better compression.
        // Maximum should be the FASTEST, not the slowest.
        var x264Preset: String {
            switch self {
            case .highQuality: return "medium"   // was "slow" — medium is ~2x faster, ~same quality
            case .balanced: return "veryfast"    // was "medium" — veryfast is ~3x faster than medium
            case .maximum: return "veryfast"     // was "slow" (bug: slowest option for "max compression")
            case .web: return "ultrafast"        // was "fast"
            }
        }

        // Quality value for VideoToolbox (-q:v 0-100, higher = better).
        // Rough CRF equivalent: 75 ~= CRF 20, 65 ~= CRF 23, 55 ~= CRF 28, 50 ~= CRF 30.
        var videotoolboxQuality: String {
            switch self {
            case .highQuality: return "75"
            case .balanced: return "65"
            case .maximum: return "55"
            case .web: return "50"
            }
        }

        /// Card copy for the preset picker.
        var blurb: String {
            switch self {
            case .highQuality: return "Minimal compression. Great for archiving."
            case .balanced: return "Good quality and smaller size. Perfect for everyday use."
            case .maximum: return "Smallest file size. Still looks great for most videos."
            case .web: return "Perfect for sharing online and social media."
            }
        }

        var iconName: String {
            switch self {
            case .highQuality: return "star.fill"
            case .balanced: return "scalemass"
            case .maximum: return "bolt.fill"
            case .web: return "globe"
            }
        }

        /// Short names for the preset cards.
        var shortName: String {
            switch self {
            case .highQuality: return "High Quality"
            case .balanced: return "Balanced"
            case .maximum: return "Maximum"
            case .web: return "Web"
            }
        }

        var footerNote: String {
            switch self {
            case .highQuality: return "Best quality. Larger files, ideal for archiving."
            case .balanced: return "Visually lossless for most sharing."
            case .maximum: return "Smallest files. Best for drafts and previews."
            case .web: return "Tuned for fast streaming and social uploads."
            }
        }

        /// Assumed total output bitrate (Mbps) for size estimates.
        /// Heuristic only — real size varies with content. Calibrated against
        /// measured encodes (≈3.1 Mbps for Balanced on real 1080p footage).
        var assumedBitrateMbps: Double {
            switch self {
            case .highQuality: return 4.5
            case .balanced: return 3.0
            case .maximum: return 1.0
            case .web: return 1.8
            }
        }
    }

    enum EncoderOption: String, CaseIterable, Identifiable {
        case hardwareH264 = "Hardware H.264"
        case hardwareHEVC = "Hardware HEVC"
        case softwareX264 = "Software x264"
        var id: String { rawValue }

        var subtitle: String {
            switch self {
            case .hardwareH264: return "Fastest (M1/M2/M3)"
            case .hardwareHEVC: return "Smaller files, fast"
            case .softwareX264: return "Best quality, slow"
            }
        }

        var videoCodec: String {
            switch self {
            case .hardwareH264: return "h264_videotoolbox"
            case .hardwareHEVC: return "hevc_videotoolbox"
            case .softwareX264: return "libx264"
            }
        }

        var shortName: String {
            switch self {
            case .hardwareH264: return "H.264"
            case .hardwareHEVC: return "HEVC"
            case .softwareX264: return "x264"
            }
        }
    }

    enum ResolutionOption: String, CaseIterable, Identifiable {
        case original = "Original"
        case r1080p = "1080p"
        case r720p = "720p"
        case r480p = "480p"
        var id: String { rawValue }

        var targetHeight: Int? {
            switch self {
            case .original: return nil
            case .r1080p: return 1080
            case .r720p: return 720
            case .r480p: return 480
            }
        }
    }

    enum CropTemplate: String, CaseIterable, Identifiable {
        case original = "Original"
        case wide = "16:9"
        case portrait = "9:16"
        case square = "1:1"
        case classic = "4:3"
        case tall = "4:5"
        case custom = "Custom…"
        var id: String { rawValue }

        /// Target aspect as w/h. nil = no constraint.
        var aspect: Double? {
            switch self {
            case .original, .custom: return nil
            case .wide: return 16.0 / 9.0
            case .portrait: return 9.0 / 16.0
            case .square: return 1.0
            case .classic: return 4.0 / 3.0
            case .tall: return 4.0 / 5.0
            }
        }
    }

    enum OutputFormat: String, CaseIterable, Identifiable {
        case mp4 = "MP4"
        case mov = "MOV"
        case mkv = "MKV"
        var id: String { rawValue }

        var ext: String { rawValue.lowercased() }
        var useFaststart: Bool { self != .mkv }
    }

    var body: some View {
        Group {
            if inputFile == nil {
                dropZoneView
            } else if settings.simpleMode {
                simpleView
            } else {
                advancedView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    if let logo = NSImage(named: "AppIcon") {
                        Image(nsImage: logo)
                            .resizable()
                            .frame(width: 22, height: 22)
                            .cornerRadius(5)
                    }
                    Text("Squeeze").font(.headline)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if #available(macOS 14, *) {
                    SettingsGearButton()
                } else {
                    Button(action: openSettingsLegacy) {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings (⌘,)")
                }
            }
        }
        .onAppear {
            ffmpegMissing = settings.checkFFmpegOnLaunch && ContentView.findFFmpeg() == nil
        }
        .alert("Replace existing file?", isPresented: $showReplaceAlert) {
            Button("Replace", role: .destructive) { runCompression() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(outputFilename) already exists beside the original. Replace it?")
        }
    }

    func openSettingsLegacy() {
        // Pre-macOS 14 fallback: try the modern selector, then the legacy one.
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    func resetAll() {
        cancelCompression()
        player?.pause()
        player = nil
        inputFile = nil
        outputFile = nil
        showSuccess = false
        errorMessage = nil
        progress = 0
        inputFileSize = 0
        outputFileSize = 0
        statusMessage = ""
        elapsedTime = ""
        etaMessage = ""
        speedMessage = ""
        encodeFps = 0
        thumbnail = nil
        probe = ProbeInfo()
        outputFilename = ""
        cropTemplate = .original
        customCropW = ""
        customCropH = ""
        trimStart = ""
        trimEnd = ""
        outputFormat = .mp4
        audioOnly = false
        showMoreOptions = false
    }

    func revealInFinder() {
        guard let url = outputFile, FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Shared components

    var dropZoneView: some View {
        dropZone
            .padding(30)
    }

    var dropZone: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.circle")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            Text("Drag & drop a video here")
                .font(.title3)
            Text("or")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("Choose File") {
                openFileDialog()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("Supports MP4, MOV, AVI, and other ffmpeg-supported formats")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8]))
        )
    }

    // MARK: - Cards and rows

    func card<Content: View>(_ content: Content, tinted: Color? = nil) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(tinted ?? Color(NSColor.controlBackgroundColor))
            )
    }

    func presetGridCardGONE(_ preset: CompressionPreset) -> some View {
        let selected = selectedPreset == preset
        return Button(action: { selectedPreset = preset }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: selected ? "circle.inset.filled" : "circle")
                        .foregroundColor(selected ? settings.accent.color : .secondary)
                    Spacer()
                    Image(systemName: preset.iconName)
                        .foregroundColor(selected ? settings.accent.color : .secondary)
                }
                Text(preset.rawValue).fontWeight(.semibold).foregroundColor(.primary)
                Text(preset.blurb).font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                if settings.showEstimates, probe.duration > 0 {
                    Text(ContentView.formatEstimate(estimateForPreset(preset)))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? settings.accent.color.opacity(0.08) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? settings.accent.color : Color.primary.opacity(0.08),
                            lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    var outputRow: some View {
        card(
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Output Location").font(.caption).foregroundColor(.secondary)
                    Text("Save beside original").font(.subheadline).lineLimit(1)
                }
                Divider().frame(height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Output Filename").font(.caption).foregroundColor(.secondary)
                    TextField("name_compressed.mp4", text: $outputFilename)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                }
            }
        )
    }

    var compressButton: some View {
        VStack(spacing: 8) {
            Button(action: startCompression) {
                HStack {
                    if isCompressing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(isCompressing ? "Compressing…" : "Compress & Save")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(settings.accent.color)
            .disabled(inputFile == nil || isCompressing)
            if isCompressing {
                Button("Cancel") { cancelCompression() }
                    .buttonStyle(.bordered)
            }
        }
    }

    var speedDisplay: String {
        guard !speedMessage.isEmpty else { return "" }
        if !settings.simpleMode, encodeFps > 0 {
            return "\(speedMessage) (\(encodeFps) fps)"
        }
        return speedMessage
    }

    var progressCard: some View {
        card(
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Compressing your video…").fontWeight(.medium)
                    Spacer()
                    Text("\(Int(progress * 100))%").fontWeight(.semibold)
                }
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(settings.accent.color)
                HStack {
                    Text(etaMessage.isEmpty ? elapsedTime : etaMessage)
                    Spacer()
                    Text(speedDisplay)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                if !settings.simpleMode, !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        )
    }

    var successCard: some View {
        card(
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Saved!").fontWeight(.semibold)
                    Spacer()
                }
                if inputFileSize > 0 && outputFileSize > 0 {
                    let ratio = Double(outputFileSize) / Double(inputFileSize)
                    Text("\(formatFileSize(inputFileSize)) → \(formatFileSize(outputFileSize)) (\(String(format: "%.0f", (1 - ratio) * 100))% smaller)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Text(outputFilename)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                HStack(spacing: 12) {
                    Button("Show in Finder") { revealInFinder() }
                        .buttonStyle(.bordered)
                    Button("Compress Another") { resetAll() }
                        .buttonStyle(.plain)
                        .foregroundColor(settings.accent.color)
                }
            },
            tinted: Color.green.opacity(0.08)
        )
    }

    func errorCard(_ message: String) -> some View {
        card(
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Compression failed").fontWeight(.medium)
                    Spacer()
                }
                Text(friendlyError(message))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Dismiss") { errorMessage = nil }
                    .buttonStyle(.plain)
                    .foregroundColor(settings.accent.color)
                    .font(.caption)
            },
            tinted: Color.orange.opacity(0.08)
        )
    }

    /// Translates common ffmpeg failures into plain language,
    /// keeping the technical tail for advanced users.
    func friendlyError(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("no such file") || lower.contains("not found") {
            return "The input file could not be read. It may have been moved or deleted."
        }
        if lower.contains("no such filter") {
            return "This build of ffmpeg is missing a required filter. Try installing ffmpeg via Homebrew: brew install ffmpeg."
        }
        if lower.contains("invalid data") || lower.contains("moov atom not found") {
            return "This file appears to be corrupt or incomplete, so it can't be compressed."
        }
        return message
    }

    var trustFooter: some View {
        HStack(spacing: 0) {
            Spacer()
            Label("Saved locally", systemImage: "lock")
            Spacer()
            Divider().frame(height: 16)
            Spacer()
            Label("No accounts", systemImage: "slash.circle")
            Spacer()
            Divider().frame(height: 16)
            Spacer()
            Label("Apple Silicon optimized", systemImage: "apple.logo")
            Spacer()
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.top, 4)
    }

    var ffmpegBanner: some View {
        card(
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ffmpeg not found").fontWeight(.medium)
                    Text("Install it with: brew install ffmpeg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
            },
            tinted: Color.orange.opacity(0.08)
        )
    }

    // MARK: - Mockup components (ui/)

    /// "4K MOV" style badge for the file card.
    var resBadge: String {
        guard probe.width > 0, let input = inputFile else { return "" }
        let m = max(probe.width, probe.height)
        let tag = m >= 3840 ? "4K" : m >= 1920 ? "1080p" : m >= 1280 ? "720p" : "\(m)p"
        return "\(tag) \(input.pathExtension.uppercased())"
    }

    /// Thumbnail play button jumps to the editor's preview.
    func openPreviewTab() {
        if settings.simpleMode { settings.simpleMode = false }
        advancedTab = .edit
    }

    var fileCardV2: some View {
        card(
            HStack(spacing: 14) {
                Button(action: openPreviewTab) {
                    ZStack(alignment: .bottomTrailing) {
                        if let thumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 220, height: 124)
                                .cornerRadius(10)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(NSColor.separatorColor).opacity(0.4))
                                    .frame(width: 220, height: 124)
                                Image(systemName: "film")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.92))
                            .shadow(radius: 4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Text(ContentView.formatDuration(probe.duration))
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(6)
                            .padding(8)
                    }
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 6) {
                    Text(inputFile?.lastPathComponent ?? "Unknown")
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 14) {
                        Label(formatFileSize(inputFileSize), systemImage: "doc")
                        Label(ContentView.formatDuration(probe.duration), systemImage: "clock")
                        if !settings.simpleMode, !resBadge.isEmpty {
                            Label(resBadge, systemImage: "video")
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: resetAll) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
        )
    }

    /// Wide 4-across preset card (simple view + advanced compress tab).
    func presetCard(_ preset: CompressionPreset) -> some View {
        let selected = selectedPreset == preset
        let estimate = estimateForPreset(preset)
        return Button(action: { selectedPreset = preset }) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: preset.iconName)
                        .font(.system(size: 28))
                        .foregroundColor(selected ? settings.accent.color : .primary)
                        .frame(maxWidth: .infinity)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selected ? settings.accent.color : .secondary)
                }
                Text(preset.shortName)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(estimate > 0 ? ContentView.formatEstimate(estimate) : "—")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.separatorColor).opacity(0.35))
                    )
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 168)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? settings.accent.color.opacity(0.08) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? settings.accent.color : Color.primary.opacity(0.08),
                            lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Compact preset mini for the advanced edit column.
    func presetMini(_ preset: CompressionPreset) -> some View {
        let selected = selectedPreset == preset
        let estimate = estimateForPreset(preset)
        return Button(action: { selectedPreset = preset }) {
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: preset.iconName)
                        .foregroundColor(selected ? settings.accent.color : .primary)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selected ? settings.accent.color : .secondary)
                        .font(.caption)
                }
                Text(preset.shortName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(estimate > 0 ? ContentView.formatEstimate(estimate).replacingOccurrences(of: "About ", with: "~ ") : "—")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(NSColor.separatorColor).opacity(0.35))
                    )
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? settings.accent.color.opacity(0.08) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? settings.accent.color : Color.primary.opacity(0.08),
                            lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    func pillButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundColor(selected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? settings.accent.color : Color(NSColor.separatorColor).opacity(0.35))
                )
        }
        .buttonStyle(.plain)
    }

    var encoderPills: some View {
        HStack(spacing: 8) {
            ForEach(EncoderOption.allCases) { enc in
                pillButton(title: enc.shortName, selected: selectedEncoder == enc) {
                    selectedEncoder = enc
                }
            }
        }
    }

    var resolutionPills: some View {
        HStack(spacing: 8) {
            ForEach(ResolutionOption.allCases) { res in
                pillButton(title: res.rawValue, selected: selectedResolution == res) {
                    selectedResolution = res
                }
            }
        }
    }

    var cropPills: some View {
        let items: [(String, CropTemplate)] = [
            ("16:9", .wide), ("9:16", .portrait), ("1:1", .square),
            ("4:3", .classic), ("4:5", .tall), ("Custom", .custom),
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                   GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            pillButton(title: "Original", selected: cropTemplate == .original) {
                cropTemplate = .original
            }
            ForEach(items, id: \.0) { label, template in
                pillButton(title: label, selected: cropTemplate == template) {
                    cropTemplate = template
                }
            }
        }
    }

    var formatPills: some View {
        HStack(spacing: 8) {
            ForEach(OutputFormat.allCases) { f in
                pillButton(title: f.rawValue, selected: outputFormat == f && !audioOnly) {
                    audioOnly = false
                    outputFormat = f
                }
            }
        }
        .disabled(audioOnly)
    }

    var saveRow: some View {
        card(
            HStack(spacing: 12) {
                Text("Save to").fontWeight(.medium)
                Menu {
                    Button("Save beside original") {}
                } label: {
                    HStack {
                        Image(systemName: "folder")
                        Text("Save beside original").lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.separatorColor).opacity(0.35))
                    )
                }
                .menuStyle(.borderlessButton)
                Divider().frame(height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Output filename").font(.caption).foregroundColor(.secondary)
                    TextField("name_compressed.mp4", text: $outputFilename)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                }
                if settings.simpleMode {
                    Button("Advanced ›") { settings.simpleMode = false }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
            }
        )
        .onChange(of: outputFormat) { _ in syncFilenameExtension() }
        .onChange(of: audioOnly) { _ in syncFilenameExtension() }
    }

    var showBiggerWarning: Bool {
        probe.duration > 0 && inputFileSize > 0 && estimateForPreset(selectedPreset) >= inputFileSize
    }

    var warnBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title2)
            Text("Output may be larger than the original.")
                .font(.subheadline)
            Spacer()
            Button("Use Maximum") { selectedPreset = .maximum }
                .buttonStyle(.borderedProminent)
                .tint(settings.accent.color)
                .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
    }

    func actionButton(title: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Button(action: startCompression) {
                HStack {
                    if isCompressing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: icon)
                    }
                    Text(isCompressing ? "Compressing…" : title)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(settings.accent.color)
            .disabled(inputFile == nil || isCompressing)
        }
    }

    var progressRow: some View {
        HStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(settings.accent.color)
            Text("\(Int(progress * 100))%")
                .fontWeight(.semibold)
                .frame(width: 52, alignment: .trailing)
            Divider().frame(height: 24)
            Text(etaMessage.isEmpty ? elapsedTime : etaMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(minWidth: 90, alignment: .leading)
            if !settings.simpleMode, !speedDisplay.isEmpty {
                Text("•").foregroundColor(.secondary)
                Text(speedDisplay).font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            Button("Cancel") { cancelCompression() }
                .buttonStyle(.bordered)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    // MARK: - Simple + advanced layouts

    var simpleView: some View {
        ScrollView {
            compressColumn
                .padding(24)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
        }
    }

    /// Shared compress column: simple mode and the advanced Compress tab.
    var compressColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            if ffmpegMissing { ffmpegBanner }
            fileCardV2
            Text("Choose Compression")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                ForEach(CompressionPreset.allCases, id: \.self) { presetCard($0) }
            }
            moreOptionsCard
            saveRow
            if showBiggerWarning { warnBanner }
            actionButton(title: "Compress & Save", icon: "play.fill")
            if isCompressing { progressRow }
            if showSuccess { successCard }
            if let error = errorMessage { errorCard(error) }
            trustFooter
        }
    }

    var moreOptionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { withAnimation { showMoreOptions.toggle() } }) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.secondary)
                    Text("More options").fontWeight(.medium)
                    Spacer()
                    Image(systemName: showMoreOptions ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            if showMoreOptions {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Encoder").font(.subheadline).foregroundColor(.secondary)
                        encoderPills
                    }
                    Divider().frame(height: 64)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Resolution").font(.subheadline).foregroundColor(.secondary)
                        resolutionPills
                    }
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    var advancedView: some View {
        ScrollView {
            VStack(spacing: 16) {
                fileCardV2
                Picker("", selection: $advancedTab) {
                    Label("Compress", systemImage: "arrow.down.to.line").tag(AdvancedTab.compress)
                    Label("Edit", systemImage: "scissors").tag(AdvancedTab.edit)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if advancedTab == .compress {
                    compressColumn
                } else {
                    editTab
                }
            }
            .padding(24)
        }
    }

    var editTab: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    previewCard
                    trimTimelineCard
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Compression Preset").font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(CompressionPreset.allCases, id: \.self) { presetMini($0) }
                    }
                    editField(label: "Encoder") { encoderPills }
                        .disabled(audioOnly)
                    editField(label: "Resolution") { resolutionPills }
                        .disabled(audioOnly)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Crop").font(.subheadline).foregroundColor(.secondary)
                        cropPills
                        if cropTemplate == .custom { customCropFields }
                        Text(cropCaption).font(.caption).foregroundColor(.secondary)
                    }
                    .disabled(audioOnly)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Format").font(.subheadline).foregroundColor(.secondary)
                        HStack {
                            formatPills
                            Spacer()
                            Image(systemName: "music.note")
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Audio Only").font(.caption).fontWeight(.medium)
                                Text("M4A").font(.caption2).foregroundColor(.secondary)
                            }
                            Toggle("", isOn: $audioOnly)
                                .toggleStyle(.switch)
                                .tint(settings.accent.color)
                                .labelsHidden()
                        }
                    }
                    saveRow
                }
                .frame(width: 380)
            }
            actionButton(title: "Export", icon: "arrow.down.to.line")
            if isCompressing { progressRow }
            if showSuccess { successCard }
            if let error = errorMessage { errorCard(error) }
            trustFooter
        }
    }

    func editField<Content: View>(_ label: String, _ content: Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline).foregroundColor(.secondary)
            content
        }
    }

    var customCropFields: some View {
        HStack(spacing: 8) {
            TextField("Width", text: $customCropW)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            Text("×").foregroundColor(.secondary)
            TextField("Height", text: $customCropH)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            Text("pixels").font(.caption).foregroundColor(.secondary)
        }
    }

    var trimStartSteps: Binding<Double> {
        Binding(
            get: { Double(trimStart) ?? 0 },
            set: { trimStart = $0 <= 0 ? "" : String(format: "%.1f", $0) }
        )
    }

    var trimEndSteps: Binding<Double> {
        Binding(
            get: { Double(trimEnd) ?? probe.duration },
            set: { trimEnd = ($0 >= probe.duration || $0 <= 0) ? "" : String(format: "%.1f", $0) }
        )
    }

    var currentTrimRange: (Double, Double) {
        ContentView.trimRange(startText: trimStart, endText: trimEnd, duration: probe.duration)
            ?? (0, probe.duration)
    }

    var trimmedLength: Double {
        let (s, e) = currentTrimRange
        return max(0, e - s)
    }

    var trimTimelineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Trim").fontWeight(.medium)
                Spacer()
                Text("Duration \(ContentView.formatDuration(trimmedLength))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.separatorColor).opacity(0.5))
                    if probe.duration > 0 {
                        let (s, e) = currentTrimRange
                        let w = max(10, geo.size.width * CGFloat((e - s) / probe.duration))
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(settings.accent.color.opacity(0.85))
                            HStack(spacing: 0) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white)
                                    .frame(width: 5)
                                    .padding(.vertical, 6)
                                    .padding(.leading, 3)
                                Spacer()
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white)
                                    .frame(width: 5)
                                    .padding(.vertical, 6)
                                    .padding(.trailing, 3)
                            }
                        }
                        .frame(width: w, height: 44)
                        .offset(x: geo.size.width * CGFloat(s / probe.duration))
                    }
                }
            }
            .frame(height: 44)
            HStack(spacing: 10) {
                Text("Start").font(.caption).foregroundColor(.secondary)
                TextField("0.0", text: $trimStart)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                if probe.duration > 0 {
                    Stepper("", value: trimStartSteps, in: 0...max(probe.duration, 1), step: 1)
                        .labelsHidden()
                }
                Spacer()
                Text("End").font(.caption).foregroundColor(.secondary)
                TextField("End", text: $trimEnd)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                if probe.duration > 0 {
                    Stepper("", value: trimEndSteps, in: 0...max(probe.duration, 1), step: 1)
                        .labelsHidden()
                }
            }
            .font(.subheadline)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    // MARK: - Edit cards (Advanced)

    var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview").font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 220)
                    .cornerRadius(12)
            }
        }
    }

    var cropCaption: String {
        guard probe.width > 0 else { return "Crop applies to the compressed output." }
        let (cw, ch) = ContentView.cropDimensions(info: probe, template: cropTemplate,
                                                  customW: Int(customCropW) ?? 0,
                                                  customH: Int(customCropH) ?? 0)
        if cw == probe.width, ch == probe.height { return "No cropping — full frame kept." }
        return "Crops to \(cw) × \(ch), centered."
    }

    func syncFilenameExtension() {
        let ext = audioOnly ? "m4a" : outputFormat.ext
        let base = outputFilename.isEmpty ? "compressed" : outputFilename
        outputFilename = ContentView.withExtension(base, ext)
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                DispatchQueue.main.async {
                    selectFile(url)
                }
            }
        }
        return true
    }

    func openFileDialog() {
        let panel = NSOpenPanel()
        panel.title = "Select Video File"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .avi]

        if panel.runModal() == .OK, let url = panel.url {
            selectFile(url)
        }
    }

    // MARK: - Compression engine (optimized)

    func startCompression() {
        // The inline banner warns when output would grow; the button always runs.
        checkReplaceAndRun()
    }

    func checkReplaceAndRun() {
        guard let input = inputFile, let output = outputURL() else { return }
        // ffmpeg refuses to write over its own input, and the failure path
        // then removes the output — which would be the original video.
        if ContentView.isSameFile(output, input) {
            errorMessage = "\(output.lastPathComponent) is the original video. Choose a different filename."
            return
        }
        if settings.askBeforeReplace,
           FileManager.default.fileExists(atPath: output.path) {
            showReplaceAlert = true
            return
        }
        runCompression()
    }

    func runCompression() {
        guard let input = inputFile, let output = outputURL() else { return }
        guard !ContentView.isSameFile(output, input) else {
            errorMessage = "\(output.lastPathComponent) is the original video. Choose a different filename."
            return
        }

        isCompressing = true
        showSuccess = false
        errorMessage = nil
        progress = 0
        statusMessage = "Starting…"
        elapsedTime = ""
        etaMessage = ""
        speedMessage = ""
        encodeFps = 0

        let preset = selectedPreset
        let encoder = selectedEncoder
        let resolution = selectedResolution
        let cropSel = cropTemplate
        let customW = Int(customCropW) ?? 0
        let customH = Int(customCropH) ?? 0
        let trimSel = ContentView.trimRange(startText: trimStart, endText: trimEnd, duration: probe.duration)
        let formatSel = outputFormat
        let audioSel = audioOnly

        DispatchQueue.global(qos: .userInitiated).async { [input] in
            let startDate = Date()

            // Elapsed-time ticker
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now(), repeating: 0.5)
            timer.setEventHandler {
                guard isCompressing else { timer.cancel(); return }
                let elapsed = Date().timeIntervalSince(startDate)
                elapsedTime = formatElapsed(elapsed)
            }
            timer.resume()

            guard let ffmpegURL = ContentView.findFFmpeg() else {
                DispatchQueue.main.async {
                    isCompressing = false
                    timer.cancel()
                    errorMessage = "ffmpeg not found. Install via `brew install ffmpeg` or bundle it in the app."
                }
                return
            }

            DispatchQueue.main.async { statusMessage = "Probing file…" }

            // One ffprobe pass → duration (progress %), audio codec (passthrough?),
            // video codec (hwaccel eligibility), dimensions (no-upscale guard), HDR flag.
            let info = ContentView.probeInput(input)
            // Trimmed jobs report progress against the trimmed length.
            let totalDuration = trimSel.map { $0.1 - $0.0 } ?? info.duration

            let args = ContentView.buildArguments(
                input: input.path,
                output: output.path,
                preset: preset,
                encoder: encoder,
                resolution: resolution,
                info: info,
                crop: cropSel,
                customCropW: customW,
                customCropH: customH,
                trim: trimSel,
                format: formatSel,
                audioOnly: audioSel
            )

            let process = Process()
            process.executableURL = ffmpegURL
            process.arguments = args

            // Use -progress pipe:1 → parse out_time_ms for accurate progress
            let progressPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = progressPipe
            process.standardError = errorPipe

            // Drain stderr on its own thread. Reading it only after waitUntilExit()
            // deadlocks once ffmpeg emits >64KB of errors (the pipe buffer fills,
            // ffmpeg blocks on write, waitUntilExit never returns).
            var stderrData = Data()
            let stderrDone = DispatchGroup()
            stderrDone.enter()
            Thread.detachNewThread {
                stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                stderrDone.leave()
            }

            DispatchQueue.main.async { currentProcess = process }

            // Parse progress output on background queue
            progressPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty,
                      let chunk = String(data: data, encoding: .utf8) else { return }
                // chunk looks like "out_time_ms=1234567\n..." repeated
                for line in chunk.components(separatedBy: "\n") {
                    if line.hasPrefix("out_time_ms=") {
                        let value = String(line.dropFirst("out_time_ms=".count))
                        if let ms = Double(value), ms > 0, totalDuration > 0 {
                            let p = min(ms / 1_000_000.0 / totalDuration, 0.999)
                            let elapsed = Date().timeIntervalSince(startDate)
                            var eta = ""
                            var speed = ""
                            if p > 0.02, elapsed > 1 {
                                eta = ContentView.formatETA(elapsed * (1 - p) / p)
                                speed = String(format: "%.0fx realtime", (p * totalDuration) / elapsed)
                            }
                            DispatchQueue.main.async {
                                progress = p
                                statusMessage = "Encoding (\(encoder.rawValue))"
                                etaMessage = eta
                                speedMessage = speed
                            }
                        }
                    } else if line.hasPrefix("frame=") {
                        // "frame= 1234" → live encode fps for the advanced view
                        let digits = line.dropFirst("frame=".count).trimmingCharacters(in: .whitespaces)
                        if let frame = Int(digits), frame > 0 {
                            let elapsed = Date().timeIntervalSince(startDate)
                            if elapsed > 0.5 {
                                let fps = Int(Double(frame) / elapsed)
                                DispatchQueue.main.async { encodeFps = fps }
                            }
                        }
                    } else if line.hasPrefix("progress=end") {
                        DispatchQueue.main.async { progress = 1.0 }
                    }
                }
            }

            // Fallback ticker if duration unknown (old file-size heuristic)
            if totalDuration <= 0 {
                DispatchQueue.main.async {
                    updateProgressFallback(process: process, output: output)
                }
            }

            do {
                try process.run()
                process.waitUntilExit()
                // All stderr collected by the reader thread at process exit.
                stderrDone.wait()
                let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
                progressPipe.fileHandleForReading.readabilityHandler = nil

                DispatchQueue.main.async {
                    timer.cancel()
                    isCompressing = false
                    currentProcess = nil
                    let elapsed = Date().timeIntervalSince(startDate)
                    elapsedTime = formatElapsed(elapsed)

                    if process.terminationStatus == 0 {
                        showSuccess = true
                        outputFile = output
                        outputFileSize = getFileSize(output)
                        progress = 1.0
                        statusMessage = ""
                        etaMessage = ""
                        speedMessage = ""
                    } else {
                        // Remove the truncated output so a failed/cancelled run
                        // never leaves a corrupt .compressed.mp4 behind.
                        if !ContentView.isSameFile(output, input) {
                            try? FileManager.default.removeItem(at: output)
                        }
                        if process.terminationStatus == SIGTERM {
                            errorMessage = "Compression cancelled."
                        } else if stderrText.isEmpty {
                            errorMessage = "Compression failed (exit \(process.terminationStatus))."
                        } else {
                            // Trim to last 2000 chars — full ffmpeg log is huge
                            errorMessage = String(stderrText.suffix(2000))
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    timer.cancel()
                    isCompressing = false
                    currentProcess = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func cancelCompression() {
        currentProcess?.terminate()
        // termination handler in startCompression will surface "cancelled"
    }

    /// Builds the optimized ffmpeg argument list.
    /// 1. VideoToolbox HW encode (~10x faster than libx264 on Apple Silicon media engine)
    /// 2. veryfast/ultrafast for software path (was slow/medium)
    /// 3. -threads 0 = use all cores
    /// 4. Downscale only when the source is LARGER than target (never upscales)
    /// 5. Audio passthrough when source is already AAC (skips re-encode entirely)
    /// 6. videotoolbox hwaccel decode for h264/hevc sources
    /// 7. HDR (PQ/HLG) → BT.709 tonemap so output isn't washed out / wrongly tagged
    static func buildArguments(
        input: String,
        output: String,
        preset: CompressionPreset,
        encoder: EncoderOption,
        resolution: ResolutionOption,
        info: ProbeInfo,
        crop: CropTemplate = .original,
        customCropW: Int = 0,
        customCropH: Int = 0,
        trim: (Double, Double)? = nil,
        format: OutputFormat = .mp4,
        audioOnly: Bool = false
    ) -> [String] {
        var args: [String] = ["-hide_banner", "-nostats", "-loglevel", "error", "-progress", "pipe:1"]

        // Decode offload only for codecs VideoToolbox actually supports —
        // mpeg4/ffv1 etc. print hwaccel init errors and fall back anyway.
        if info.probed, let videoCodec = info.videoCodec, videoCodec == "h264" || videoCodec == "hevc" {
            args += ["-hwaccel", "videotoolbox"]
        }

        args += ["-i", input]

        // --- Audio-only extraction: no video stream, no filters, no video cap ---
        if audioOnly {
            if let (s, e) = trim {
                args += ["-ss", String(s), "-to", String(e)]
            }
            args += ["-vn"]
            if info.probed, let audioCodec = info.audioCodec, audioCodec == "aac" {
                args += ["-c:a", "copy"]
            } else {
                args += ["-c:a", "aac", "-b:a", "128k", "-ac", "2"]
            }
            args += ["-threads", "0", "-movflags", "+faststart", "-y", output]
            return args
        }

        args += ["-c:v", encoder.videoCodec]

        // Bitrate ceiling: quality (-q:v/-crf) drives the encode, -maxrate caps
        // runaway size. Capped at the source bitrate — re-encoding can't invent
        // quality, so spending more bits than the source did only grows the file.
        let cap = bitrateCapMbps(preset: preset, sourceBitrateBps: info.bitrate)
        let capArg = formatBitrateMbps(cap)
        let bufArg = formatBitrateMbps(cap * 2)

        switch encoder {
        case .hardwareH264, .hardwareHEVC:
            // Quality-controlled VBR — closest to CRF behavior, much faster than libx264
            args += ["-q:v", preset.videotoolboxQuality]
            args += ["-maxrate", capArg, "-bufsize", bufArg]
            args += ["-allow_sw", "1"]   // fall back to SW for odd pixel formats instead of failing
            args += ["-prio_speed", "1"] // prioritize encode speed on Apple Silicon media engine
            args += ["-realtime", "0"]
        case .softwareX264:
            args += ["-crf", preset.crf]
            args += ["-preset", preset.x264Preset]
            args += ["-maxrate", capArg, "-bufsize", bufArg]
        }

        var filters: [String] = []
        if info.isHDR {
            // PQ/HLG → SDR: linearize, compress highlights with hable curve, then
            // retag as BT.709 — without the setparams the output keeps smpte2084
            // metadata and players render tonemapped pixels through a PQ curve.
            filters.append("format=gbrpf32le,tonemap=hable,setparams=color_trc=bt709:color_primaries=bt709:colorspace=bt709:range=tv,format=yuv420p")
        }
        // Crop first (centered), then the resolution scale applies to cropped dims.
        let (cw, ch) = ContentView.cropDimensions(info: info, template: crop, customW: customCropW, customH: customCropH)
        if let cropF = ContentView.cropFilterString(sw: info.width, sh: info.height, cw: cw, ch: ch) {
            filters.append(cropF)
        }
        if let scale = scaledFilter(resolution: resolution, width: cw, height: ch) {
            filters.append(scale)
        }
        if !filters.isEmpty {
            args += ["-vf", filters.joined(separator: ",")]
        }
        args += ["-pix_fmt", "yuv420p"]

        // Audio: passthrough if already AAC (lossless, free); else re-encode once.
        if info.probed {
            if let audioCodec = info.audioCodec {
                if audioCodec == "aac" {
                    args += ["-c:a", "copy"]
                } else {
                    args += ["-c:a", "aac", "-b:a", "128k", "-ac", "2"]
                }
            }
            // probed with no audio stream → omit audio args entirely
        } else {
            // ffprobe unavailable — container default (aac for mp4) is fine
            args += ["-c:a", "aac", "-b:a", "128k", "-ac", "2"]
        }

        // Accurate (output-side) trim — slower to start on long files,
        // but frame-exact, unlike input seeking.
        if let (s, e) = trim {
            args += ["-ss", String(s), "-to", String(e)]
        }

        args += ["-threads", "0"] // auto = all performance cores
        if format.useFaststart {
            args += ["-movflags", "+faststart"]
        }
        args += ["-y", output]
        return args
    }

    /// Downscale filter that NEVER upscales. Landscape limits height, portrait limits
    /// width, so "1080p" means 1920x1080 for landscape and 1080x1920 for portrait.
    static func scaledFilter(resolution: ResolutionOption, width: Int, height: Int) -> String? {
        guard let target = resolution.targetHeight else { return nil }
        if width <= 0 || height <= 0 {
            // Dimensions unknown — min() guard still prevents upscaling a small source.
            return "scale=-2:min(\(target)\\,ih)"
        }
        guard let d = scaledDimensions(resolution: resolution, width: width, height: height) else {
            return nil
        }
        if d.h == target { return "scale=-2:\(d.h)" }
        return "scale=\(d.w):-2"
    }

    /// Output dimensions after the resolution policy (nil = keep input dims).
    static func scaledDimensions(resolution: ResolutionOption, width: Int, height: Int) -> (w: Int, h: Int)? {
        guard let target = resolution.targetHeight else { return nil }
        guard width > 0, height > 0 else { return nil }
        if width >= height {
            guard height > target else { return nil }
            let w = (width * target) / height
            return (w - w % 2, target)
        } else {
            guard width > target else { return nil }
            let h = (height * target) / width
            return (target, h - h % 2)
        }
    }

    /// Centered crop dimensions for a template (even, clamped to source).
    /// Returns source dims when no cropping applies.
    static func cropDimensions(info: ProbeInfo, template: CropTemplate, customW: Int, customH: Int) -> (w: Int, h: Int) {
        let sw = info.width, sh = info.height
        guard sw > 0, sh > 0 else { return (sw, sh) }
        var tw: Int, th: Int
        if template == .custom {
            tw = min(max(customW, 0), sw)
            th = min(max(customH, 0), sh)
            guard tw > 0, th > 0 else { return (sw, sh) }
        } else if let aspect = template.aspect {
            if Double(sw) / Double(sh) > aspect {
                th = sh
                tw = Int(Double(sh) * aspect)
            } else {
                tw = sw
                th = Int(Double(sw) / aspect)
            }
        } else {
            return (sw, sh)
        }
        tw -= tw % 2
        th -= th % 2
        guard tw > 0, th > 0 else { return (sw, sh) }
        return (tw, th)
    }

    /// Centered crop filter, or nil when the crop equals the source.
    static func cropFilterString(sw: Int, sh: Int, cw: Int, ch: Int) -> String? {
        guard sw > 0, sh > 0, cw > 0, ch > 0 else { return nil }
        guard cw != sw || ch != sh else { return nil }
        return "crop=\(cw):\(ch):\((sw - cw) / 2):\((sh - ch) / 2)"
    }

    /// Final output dimensions after crop then scale (for estimates + captions).
    static func finalDimensions(cropW: Int, cropH: Int, resolution: ResolutionOption) -> (w: Int, h: Int) {
        return scaledDimensions(resolution: resolution, width: cropW, height: cropH) ?? (cropW, cropH)
    }

    /// Validated trim range in seconds, or nil for full length.
    static func trimRange(startText: String, endText: String, duration: Double) -> (Double, Double)? {
        guard duration > 0 else { return nil }
        let s = Double(startText.trimmingCharacters(in: .whitespaces)) ?? 0
        let eRaw = endText.trimmingCharacters(in: .whitespaces)
        let e = eRaw.isEmpty ? duration : (Double(eRaw) ?? duration)
        let cs = min(max(s, 0), duration)
        let ce = min(max(e, 0), duration)
        guard ce - cs > 0.1 else { return nil }
        if cs <= 0.05, ce >= duration - 0.05 { return nil } // effectively full length
        return (cs, ce)
    }

    static func effectiveDuration(info: ProbeInfo, startText: String, endText: String) -> Double {
        if let (s, e) = trimRange(startText: startText, endText: endText, duration: info.duration) {
            return e - s
        }
        return info.duration
    }

    /// Filename with its extension swapped (for format / audio-only changes).
    static func withExtension(_ name: String, _ ext: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "compressed.\(ext)" }
        let base = URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent
        let clean = base.isEmpty ? "compressed" : base
        return "\(clean).\(ext)"
    }

    /// Locate an ffmpeg-family binary robustly (old code hardcoded
    /// /opt/homebrew/bin/ffmpeg and broke on Intel / MacPorts installs).
    static func findTool(_ name: String) -> String? {
        // 1. Bundled binary (best for distribution)
        if let bundled = Bundle.main.url(forResource: name, withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled.path
        }
        // 2. Common Homebrew / system paths
        let candidates = [
            "/opt/homebrew/bin/\(name)", // Apple Silicon
            "/usr/local/bin/\(name)",    // Intel Homebrew
            "/usr/bin/\(name)",
            "/opt/local/bin/\(name)"     // MacPorts
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        // 3. PATH lookup
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = [name]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        try? which.run()
        which.waitUntilExit()
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    static func findFFmpeg() -> URL? {
        findTool("ffmpeg").map { URL(fileURLWithPath: $0) }
    }

    /// One ffprobe pass: duration, codecs, dimensions, HDR flag.
    /// Returns zeroed info if ffprobe is missing or the file is unparseable —
    /// callers fall back to conservative defaults.
    static func probeInput(_ url: URL) -> ProbeInfo {
        var info = ProbeInfo()
        guard let ffprobe = findTool("ffprobe") else { return info }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobe)
        process.arguments = [
            "-v", "error", "-of", "json",
            "-show_entries", "format=duration,bit_rate:stream=codec_type,codec_name,width,height,avg_frame_rate,sample_rate,channels,color_transfer,disposition",
            url.path
        ]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            // ffprobe exits non-zero on unreadable files yet still prints "{}"
            // — trust the exit status, or a missing file looks "probed".
            guard process.terminationStatus == 0 else { return info }
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return info
            }
            info.probed = true
            if let format = obj["format"] as? [String: Any] {
                if let duration = format["duration"] as? String {
                    info.duration = Double(duration) ?? 0
                }
                if let bitrate = format["bit_rate"] as? String {
                    info.bitrate = Double(bitrate) ?? 0
                }
            }
            if let streams = obj["streams"] as? [[String: Any]] {
                for stream in streams {
                    guard let type = stream["codec_type"] as? String else { continue }
                    let disposition = stream["disposition"] as? [String: Any]
                    let isCoverArt = (disposition?["attached_pic"] as? Int) == 1
                    if type == "video", !isCoverArt, info.videoCodec == nil {
                        info.videoCodec = stream["codec_name"] as? String
                        info.width = stream["width"] as? Int ?? 0
                        info.height = stream["height"] as? Int ?? 0
                        info.fps = parseFrameRate(stream["avg_frame_rate"] as? String)
                        if let transfer = stream["color_transfer"] as? String {
                            info.isHDR = transfer == "smpte2084" || transfer == "arib-67"
                        }
                    } else if type == "audio", info.audioCodec == nil {
                        info.audioCodec = stream["codec_name"] as? String
                        if let rate = stream["sample_rate"] as? String {
                            info.audioSampleRate = Int(rate) ?? 0
                        }
                        info.audioChannels = stream["channels"] as? Int ?? 0
                    }
                }
            }
        } catch {
            return info
        }
        return info
    }

    /// Bitrate ceiling (Mbps) for -maxrate. Preset caps keep normal encodes
    /// untouched; the source-bitrate cap stops already-compressed inputs
    /// from ballooning (e.g. a 24 MB file becoming 28 MB).
    static func bitrateCapMbps(preset: CompressionPreset, sourceBitrateBps: Double) -> Double {
        let presetCap: Double
        switch preset {
        case .highQuality: presetCap = 12
        case .balanced: presetCap = 8
        case .maximum: presetCap = 4
        case .web: presetCap = 5
        }
        guard sourceBitrateBps > 0 else { return presetCap }
        return min(presetCap, sourceBitrateBps / 1_000_000)
    }

    /// "8M", "2.5M" — ffmpeg bitrate literals.
    static func formatBitrateMbps(_ mbps: Double) -> String {
        let s = String(format: "%.1f", mbps)
        return (s.hasSuffix(".0") ? String(s.dropLast(2)) : s) + "M"
    }

    /// Parses ffprobe's "num/den" frame rate (e.g. "30/1", "30000/1001").
    static func parseFrameRate(_ value: String?) -> Double {
        guard let value, !value.isEmpty else { return 0 }
        let parts = value.split(separator: "/").compactMap { Double($0) }
        guard parts.count == 2, parts[1] != 0 else { return parts.first ?? 0 }
        return parts[0] / parts[1]
    }

    /// Container description from file extension.
    static func formatName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mov": return "QuickTime (.MOV)"
        case "mp4", "m4v": return "MPEG-4 (.MP4)"
        case "avi": return "AVI (.AVI)"
        case "mkv": return "Matroska (.MKV)"
        case "webm": return "WebM (.WEBM)"
        case "m2ts", "mts": return "MPEG-TS (.M2TS)"
        default:
            let ext = url.pathExtension.uppercased()
            return ext.isEmpty ? "Video" : "Video (.\(ext))"
        }
    }

    /// Single entry point for choosing a file (drop zone + dialog).
    /// Probes once for display (details, estimates, thumbnail) — the engine
    /// re-probes at encode time so these stay display-only.
    func selectFile(_ url: URL) {
        player?.pause()
        player = AVPlayer(url: url)
        inputFile = url
        inputFileSize = getFileSize(url)
        outputFilename = url.deletingPathExtension().lastPathComponent + "_compressed.mp4"
        outputFile = nil
        showSuccess = false
        errorMessage = nil
        progress = 0
        outputFileSize = 0
        statusMessage = ""
        elapsedTime = ""
        etaMessage = ""
        speedMessage = ""
        thumbnail = nil
        probe = ProbeInfo()
        cropTemplate = .original
        customCropW = ""
        customCropH = ""
        trimStart = ""
        trimEnd = ""
        outputFormat = .mp4
        audioOnly = false

        DispatchQueue.global(qos: .userInitiated).async { [url] in
            let info = ContentView.probeInput(url)
            DispatchQueue.main.async { probe = info }
            loadThumbnail(for: url, duration: info.duration)
        }
    }

    /// Video thumbnail via AVFoundation, ~10% into the file.
    func loadThumbnail(for url: URL, duration: Double) {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        let seconds = duration > 0 ? min(max(duration * 0.1, 0.5), 10) : 1.0
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        generator.generateCGImageAsynchronously(for: time) { image, _, _ in
            guard let image else { return }
            DispatchQueue.main.async {
                thumbnail = NSImage(cgImage: image, size: .zero)
            }
        }
    }

    /// True when both URLs name the same file: same file identity if the
    /// output exists, else the same path compared case-insensitively (APFS).
    static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        let ra = a.standardizedFileURL.resolvingSymlinksInPath()
        let rb = b.standardizedFileURL.resolvingSymlinksInPath()
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        if let ia = try? ra.resourceValues(forKeys: key).fileResourceIdentifier,
           let ib = try? rb.resourceValues(forKeys: key).fileResourceIdentifier {
            return ia.isEqual(ib)
        }
        return ra.path.lowercased() == rb.path.lowercased()
    }

    /// Output URL: beside the original, under the editable filename,
    /// with the extension following the format (or .m4a for audio-only).
    func outputURL() -> URL? {
        guard let input = inputFile else { return nil }
        let ext = audioOnly ? "m4a" : outputFormat.ext
        var name = outputFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "compressed" }
        name = name.replacingOccurrences(of: "/", with: "-")
        name = ContentView.withExtension(name, ext)
        return input.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// Display estimate honoring trim length, crop/scale pixel ratio and audio-only.
    func estimateForPreset(_ preset: CompressionPreset) -> Int64 {
        let dur = ContentView.effectiveDuration(info: probe, startText: trimStart, endText: trimEnd)
        guard dur > 0 else { return 0 }
        if audioOnly {
            if probe.audioCodec == "aac", inputFileSize > 0, probe.duration > 0 {
                return Int64(Double(inputFileSize) * (dur / probe.duration) * 0.08)
            }
            return Int64(16000 * dur)
        }
        var pixels = 1.0
        if probe.width > 0, probe.height > 0 {
            let (cw, ch) = ContentView.cropDimensions(info: probe, template: cropTemplate,
                                                      customW: Int(customCropW) ?? 0,
                                                      customH: Int(customCropH) ?? 0)
            let (fw, fh) = ContentView.finalDimensions(cropW: cw, cropH: ch,
                                                        resolution: selectedResolution)
            if fw > 0, fh > 0 {
                pixels = max(0.15, min(1.0, Double(fw * fh) / Double(probe.width * probe.height)))
            }
        }
        return Int64(Double(ContentView.estimatedBytes(preset: preset, duration: dur)) * pixels)
    }

    /// Heuristic output estimate: assumed bitrate × duration. Display-only.
    static func estimatedBytes(preset: CompressionPreset, duration: Double) -> Int64 {
        guard duration > 0 else { return 0 }
        return Int64(preset.assumedBitrateMbps * 1_000_000 / 8 * duration)
    }

    static func formatEstimate(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "" }
        let mb = Double(bytes) / 1_000_000
        if mb >= 1000 { return String(format: "About %.1f GB", mb / 1000) }
        return "About \(Int(mb.rounded())) MB"
    }

    static func formatDuration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "--:--" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func formatETA(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "" }
        if seconds < 1 { return "Almost done" }
        if seconds < 60 { return "About \(Int(seconds)) sec left" }
        let m = Int(seconds) / 60
        return "About \(m) min left"
    }

    func updateProgressFallback(process: Process, output: URL) {
        guard process.isRunning else { return }

        // Simple progress based on output file growth
        let currentSize = getFileSize(output)
        let estimatedTotal = max(inputFileSize / 3, 1) // Rough estimate
        progress = min(Double(currentSize) / Double(estimatedTotal), 0.99)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            updateProgressFallback(process: process, output: output)
        }
    }

    func getFileSize(_ url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }

    func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    func formatElapsed(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let m = total / 60
        let s = total % 60
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return String(format: "%.1fs", interval)
    }
}

#Preview {
    ContentView()
}
