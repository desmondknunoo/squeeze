import SwiftUI
import AppKit

/// Result of a single ffprobe pass — drives codec/scale/HDR decisions.
struct ProbeInfo {
    var probed = false
    var duration: Double = 0
    var videoCodec: String?
    var audioCodec: String?
    var width: Int = 0
    var height: Int = 0
    var isHDR = false
}

struct ContentView: View {
    @State private var inputFile: URL?
    @State private var outputFile: URL?
    @State private var isCompressing = false
    @State private var progress: Double = 0
    @State private var selectedPreset: CompressionPreset = .balanced
    @State private var selectedEncoder: EncoderOption = .hardwareH264
    @State private var selectedResolution: ResolutionOption = .original
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @State private var outputPath: String = ""
    @State private var inputFileSize: Int64 = 0
    @State private var outputFileSize: Int64 = 0
    @State private var statusMessage: String = ""
    @State private var elapsedTime: String = ""
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

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "film")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading) {
                    Text("Video Compressor")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Compress videos locally using ffmpeg")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            // Main content
            VStack(spacing: 20) {
                if inputFile == nil {
                    dropZone
                } else {
                    fileInfo
                    presetPicker
                    encoderPicker
                    resolutionPicker
                    compressionButton
                    if isCompressing {
                        progressView
                    }
                    if showSuccess {
                        successView
                    }
                    if let error = errorMessage {
                        errorView(error)
                    }
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
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

    var fileInfo: some View {
        HStack {
            Image(systemName: "doc.video")
                .font(.system(size: 32))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading) {
                Text(inputFile?.lastPathComponent ?? "Unknown")
                    .font(.headline)
                Text(formatFileSize(inputFileSize))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: {
                cancelCompression()
                inputFile = nil
                outputFile = nil
                showSuccess = false
                errorMessage = nil
                progress = 0
                inputFileSize = 0
                outputFileSize = 0
                statusMessage = ""
                elapsedTime = ""
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    var presetPicker: some View {
        HStack {
            Text("Compression:")
                .fontWeight(.medium)
            Picker("Preset", selection: $selectedPreset) {
                ForEach(CompressionPreset.allCases, id: \.self) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            Spacer()
        }
    }

    var encoderPicker: some View {
        HStack {
            Text("Encoder:")
                .fontWeight(.medium)
                .frame(width: 100, alignment: .leading)
            Picker("Encoder", selection: $selectedEncoder) {
                ForEach(EncoderOption.allCases) { enc in
                    Text("\(enc.rawValue) — \(enc.subtitle)").tag(enc)
                }
            }
            .pickerStyle(.menu)
            Spacer()
        }
    }

    var resolutionPicker: some View {
        HStack {
            Text("Resolution:")
                .fontWeight(.medium)
                .frame(width: 100, alignment: .leading)
            Picker("Resolution", selection: $selectedResolution) {
                ForEach(ResolutionOption.allCases) { res in
                    Text(res.rawValue).tag(res)
                }
            }
            .pickerStyle(.segmented)
            Spacer()
        }
    }

    var compressionButton: some View {
        HStack {
            Button(action: startCompression) {
                HStack {
                    if isCompressing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                    Text(isCompressing ? "Compressing..." : "Compress Video")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(inputFile == nil || isCompressing)

            if isCompressing {
                Button("Cancel") { cancelCompression() }
                    .buttonStyle(.bordered)
            }
        }
    }

    var progressView: some View {
        VStack(spacing: 8) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            HStack {
                Text("\(Int(progress * 100))% complete")
                Text("·")
                Text(statusMessage.isEmpty ? elapsedTime : "\(statusMessage) · \(elapsedTime)")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    var successView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Compression complete! (\(elapsedTime))")
                    .fontWeight(.medium)
            }
            if inputFileSize > 0 && outputFileSize > 0 {
                let ratio = Double(outputFileSize) / Double(inputFileSize)
                Text("\(formatFileSize(inputFileSize)) → \(formatFileSize(outputFileSize)) (\(String(format: "%.0f", (1 - ratio) * 100))% reduction)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Button("Save Compressed File") {
                saveCompressedFile()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
    }

    func errorView(_ message: String) -> some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Error")
                    .fontWeight(.medium)
            }
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                DispatchQueue.main.async {
                    inputFile = url
                    inputFileSize = getFileSize(url)
                    outputPath = url.deletingPathExtension().appendingPathExtension("compressed.mp4").path
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
            inputFile = url
            inputFileSize = getFileSize(url)
            outputPath = url.deletingPathExtension().appendingPathExtension("compressed.mp4").path
        }
    }

    // MARK: - Compression engine (optimized)

    func startCompression() {
        guard let input = inputFile else { return }

        let output = URL(fileURLWithPath: outputPath)
        isCompressing = true
        showSuccess = false
        errorMessage = nil
        progress = 0
        statusMessage = "Starting…"
        elapsedTime = ""

        let preset = selectedPreset
        let encoder = selectedEncoder
        let resolution = selectedResolution

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
            let totalDuration = info.duration

            let args = ContentView.buildArguments(
                input: input.path,
                output: output.path,
                preset: preset,
                encoder: encoder,
                resolution: resolution,
                info: info
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
                            DispatchQueue.main.async {
                                progress = p
                                statusMessage = "Encoding (\(encoder.rawValue))"
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
                        outputFileSize = getFileSize(output)
                        progress = 1.0
                        statusMessage = ""
                    } else {
                        // Remove the truncated output so a failed/cancelled run
                        // never leaves a corrupt .compressed.mp4 behind.
                        try? FileManager.default.removeItem(at: output)
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
        info: ProbeInfo
    ) -> [String] {
        var args: [String] = ["-hide_banner", "-nostats", "-loglevel", "error", "-progress", "pipe:1"]

        // Decode offload only for codecs VideoToolbox actually supports —
        // mpeg4/ffv1 etc. print hwaccel init errors and fall back anyway.
        if info.probed, let videoCodec = info.videoCodec, videoCodec == "h264" || videoCodec == "hevc" {
            args += ["-hwaccel", "videotoolbox"]
        }

        args += ["-i", input]
        args += ["-c:v", encoder.videoCodec]

        switch encoder {
        case .hardwareH264, .hardwareHEVC:
            // Quality-controlled VBR — closest to CRF behavior, much faster than libx264
            args += ["-q:v", preset.videotoolboxQuality]
            args += ["-allow_sw", "1"]   // fall back to SW for odd pixel formats instead of failing
            args += ["-prio_speed", "1"] // prioritize encode speed on Apple Silicon media engine
            args += ["-realtime", "0"]
        case .softwareX264:
            args += ["-crf", preset.crf]
            args += ["-preset", preset.x264Preset]
        }

        var filters: [String] = []
        if info.isHDR {
            // PQ/HLG → SDR: linearize, compress highlights with hable curve, then
            // retag as BT.709 — without the setparams the output keeps smpte2084
            // metadata and players render tonemapped pixels through a PQ curve.
            filters.append("format=gbrpf32le,tonemap=hable,setparams=color_trc=bt709:color_primaries=bt709:colorspace=bt709:range=tv,format=yuv420p")
        }
        if let scale = scaledFilter(resolution: resolution, width: info.width, height: info.height) {
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

        args += ["-threads", "0"] // auto = all performance cores
        args += ["-movflags", "+faststart"]
        args += ["-y", output]
        return args
    }

    /// Downscale filter that NEVER upscales. Landscape limits height, portrait limits
    /// width, so "1080p" means 1920x1080 for landscape and 1080x1920 for portrait.
    static func scaledFilter(resolution: ResolutionOption, width: Int, height: Int) -> String? {
        guard let target = resolution.targetHeight else { return nil }
        guard width > 0, height > 0 else {
            // Dimensions unknown — min() guard still prevents upscaling a small source.
            return "scale=-2:min(\(target)\\,ih)"
        }
        if width >= height {
            guard height > target else { return nil }
            return "scale=-2:\(target)"
        } else {
            guard width > target else { return nil }
            return "scale=\(target):-2"
        }
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
            "-show_entries", "format=duration:stream=codec_type,codec_name,width,height,color_transfer,disposition",
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
            if let format = obj["format"] as? [String: Any],
               let duration = format["duration"] as? String {
                info.duration = Double(duration) ?? 0
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
                        if let transfer = stream["color_transfer"] as? String {
                            info.isHDR = transfer == "smpte2084" || transfer == "arib-67"
                        }
                    } else if type == "audio", info.audioCodec == nil {
                        info.audioCodec = stream["codec_name"] as? String
                    }
                }
            }
        } catch {
            return info
        }
        return info
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

    func saveCompressedFile() {
        guard let input = inputFile else { return }

        let panel = NSSavePanel()
        panel.title = "Save Compressed Video"
        panel.nameFieldStringValue = input.deletingPathExtension().lastPathComponent + "_compressed.mp4"
        panel.allowedContentTypes = [.mpeg4Movie]

        if panel.runModal() == .OK, let outputUrl = panel.url {
            try? FileManager.default.removeItem(at: outputUrl)
            try? FileManager.default.moveItem(atPath: outputPath, toPath: outputUrl.path)
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
