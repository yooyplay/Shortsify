import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - App

@main
struct ShortsifyApp: App {
    var body: some Scene {
        WindowGroup("Shortsify") {
            RootView()
        }
        .windowResizability(.contentSize)
    }
}

struct RootView: View {
    @State private var installer = FFmpegInstaller()

    var body: some View {
        switch installer.phase {
        case .checking:
            Color.clear.frame(width: 500, height: 520)
                .onAppear { installer.checkOrInstall() }
        case .ready:
            ContentView()
        case .downloading(let p):
            SetupView(progress: p)
        case .failed(let msg):
            SetupFailedView(message: msg) { installer.retry() }
        }
    }
}

// MARK: - Setup Views

struct SetupView: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 8) {
                Text("Setting up Shortsify")
                    .font(.title2.weight(.bold))
                Text("Downloading ffmpeg — this only happens once.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 300)
                Text(progress > 0 ? "\(Int(progress * 100))%" : "Starting...")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text("ffmpeg is an open-source video tool used by Shortsify to convert your videos.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(48)
        .frame(width: 500, height: 400)
    }
}

struct SetupFailedView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 52))
                .foregroundStyle(.red)

            Text("Setup failed")
                .font(.title2.weight(.bold))

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .padding(48)
        .frame(width: 500, height: 380)
    }
}

// MARK: - Aspect Ratio

enum AspectRatio: String, CaseIterable, Identifiable {
    case vertical   = "9:16"
    case square     = "1:1"
    case portrait   = "4:5"
    case horizontal = "16:9"

    var id: String { rawValue }

    var width: Int {
        switch self { case .vertical: 1080; case .square: 1080; case .portrait: 1080; case .horizontal: 1920 }
    }
    var height: Int {
        switch self { case .vertical: 1920; case .square: 1080; case .portrait: 1350; case .horizontal: 1080 }
    }
    var platform: String {
        switch self {
        case .vertical:   "Shorts / TikTok"
        case .square:     "Instagram"
        case .portrait:   "IG Feed"
        case .horizontal: "YouTube"
        }
    }
    var symbol: String {
        switch self {
        case .vertical:   "iphone"
        case .square:     "square"
        case .portrait:   "rectangle.portrait"
        case .horizontal: "rectangle"
        }
    }
    var suffix: String { rawValue.replacingOccurrences(of: ":", with: "x") }
}

// MARK: - Item

enum ItemStatus: Equatable {
    case queued, converting, done, failed(String)
}

@Observable
final class ConversionItem: Identifiable {
    let id = UUID()
    let inputURL: URL
    let ratio: AspectRatio
    var outputURL: URL?
    var status: ItemStatus = .queued
    var progress: Double = 0
    var filename: String { inputURL.lastPathComponent }
    init(_ url: URL, ratio: AspectRatio) { inputURL = url; self.ratio = ratio }
}

// MARK: - Converter

@MainActor
@Observable
final class Converter {
    var items: [ConversionItem] = []
    var selectedRatios: Set<AspectRatio> = [.vertical]
    private var busy = false

    static let videoExts = Set(["mp4","mov","avi","mkv","m4v","webm","flv","wmv","ts","mts","3gp"])

    func addURLs(_ urls: [URL]) {
        let fm = FileManager.default
        var videoURLs: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                while let child = enumerator?.nextObject() as? URL {
                    if Self.videoExts.contains(child.pathExtension.lowercased()) { videoURLs.append(child) }
                }
            } else if Self.videoExts.contains(url.pathExtension.lowercased()) {
                videoURLs.append(url)
            }
        }
        // One item per (file × selected ratio)
        let ratios = AspectRatio.allCases.filter { selectedRatios.contains($0) }
        let added = videoURLs.flatMap { url in ratios.map { ConversionItem(url, ratio: $0) } }
        items.append(contentsOf: added)
        processNext()
    }

    func clearFinished() {
        items.removeAll {
            switch $0.status { case .done, .failed: true; default: false }
        }
    }

    private func processNext() {
        guard !busy, let next = items.first(where: { $0.status == .queued }) else { return }
        busy = true
        convert(next)
    }

    private func convert(_ item: ConversionItem) {
        guard let ffmpeg = FFmpegLocator.installedPath else {
            item.status = .failed("ffmpeg not found")
            busy = false; processNext(); return
        }

        let ratio = item.ratio
        let outURL = item.inputURL.deletingLastPathComponent()
            .appendingPathComponent(item.inputURL.deletingPathExtension().lastPathComponent + "_\(ratio.suffix)")
            .appendingPathExtension(item.inputURL.pathExtension)

        item.outputURL = outURL
        item.status = .converting
        item.progress = 0

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ffmpeg)
        proc.arguments = [
            "-i", item.inputURL.path,
            "-vf", "scale=\(ratio.width):\(ratio.height):force_original_aspect_ratio=decrease,pad=\(ratio.width):\(ratio.height):(ow-iw)/2:(oh-ih)/2:black",
            "-c:v", "libx264", "-crf", "18", "-preset", "fast",
            "-c:a", "aac", "-b:a", "192k",
            "-movflags", "+faststart", "-y", outURL.path
        ]

        let pipe = Pipe()
        proc.standardError = pipe
        proc.standardOutput = FileHandle.nullDevice

        final class PS: @unchecked Sendable {
            var buf = ""; var total: Double = 0; var found = false
        }
        let ps = PS()

        pipe.fileHandleForReading.readabilityHandler = { handle in
            guard let text = String(data: handle.availableData, encoding: .utf8) else { return }
            if !ps.found {
                ps.buf += text
                if let d = Converter.parseDuration(ps.buf) { ps.total = d; ps.found = true }
            }
            if let t = Converter.parseTime(text), ps.total > 0 {
                let p = min(t / ps.total, 0.99)
                DispatchQueue.main.async { item.progress = p }
            }
        }

        proc.terminationHandler = { [weak self] p in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                if p.terminationStatus == 0 { item.progress = 1; item.status = .done }
                else { item.status = .failed("Conversion failed") }
                self?.busy = false
                self?.processNext()
            }
        }

        try? proc.run()
    }

    // MARK: Parsing

    nonisolated static func parseDuration(_ t: String) -> Double? {
        timestamp(#"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)"#, in: t, last: false)
    }
    nonisolated static func parseTime(_ t: String) -> Double? {
        timestamp(#"time=(\d+):(\d+):(\d+(?:\.\d+)?)"#, in: t, last: true)
    }
    nonisolated private static func timestamp(_ pattern: String, in text: String, last: Bool) -> Double? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let all = re.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard let m = last ? all.last : all.first else { return nil }
        let h = Double(ns.substring(with: m.range(at: 1))) ?? 0
        let mn = Double(ns.substring(with: m.range(at: 2))) ?? 0
        let s = Double(ns.substring(with: m.range(at: 3))) ?? 0
        return h * 3600 + mn * 60 + s
    }
}

// MARK: - Content View

struct ContentView: View {
    @State private var converter = Converter()
    @State private var isTargeted = false

    var body: some View {
        @Bindable var conv = converter
        VStack(spacing: 0) {
            ResolutionPicker(selected: $conv.selectedRatios)
                .padding(.horizontal, 20).padding(.vertical, 14)

            Divider()

            if converter.items.isEmpty {
                DropZoneView(isTargeted: isTargeted)
                    .onTapGesture { pickFiles() }
            } else {
                FileListView(items: converter.items)
            }

            if !converter.items.isEmpty {
                Divider()
                BottomBar(converter: converter, onAdd: pickFiles)
            }
        }
        .frame(width: 500, height: 520)
        .animation(.easeInOut(duration: 0.2), value: converter.items.isEmpty)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            loadDrop(providers)
            return true
        }
    }

    func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsOtherFileTypes = true
        panel.prompt = "Add"
        panel.message = "Choose video files or a folder"
        if panel.runModal() == .OK { converter.addURLs(panel.urls) }
    }

    func loadDrop(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { converter.addURLs(urls) }
    }
}

// MARK: - Resolution Picker

// MARK: - Resolution Picker (multi-select)

struct ResolutionPicker: View {
    @Binding var selected: Set<AspectRatio>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Output formats")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(AspectRatio.allCases) { ratio in
                    RatioButton(ratio: ratio, isSelected: selected.contains(ratio)) {
                        if selected.contains(ratio) {
                            if selected.count > 1 { selected.remove(ratio) }
                        } else {
                            selected.insert(ratio)
                        }
                    }
                }
            }
            if selected.count > 1 {
                Text("Each video will be converted to \(selected.count) formats")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RatioButton: View {
    let ratio: AspectRatio
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: ratio.symbol)
                    .font(.system(size: 15))
                Text(ratio.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                Text(ratio.platform)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Drop Zone

struct DropZoneView: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                .scaleEffect(isTargeted ? 1.1 : 1)
            Text("Drop videos or a folder here")
                .font(.title2.weight(.semibold))
            Text("or click to choose")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                              style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                .padding(20)
        )
        .contentShape(Rectangle())
        .animation(.spring(duration: 0.2), value: isTargeted)
    }
}

// MARK: - File List

struct FileListView: View {
    let items: [ConversionItem]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    FileRowView(item: item)
                    if item.id != items.last?.id { Divider().padding(.leading, 48) }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct FileRowView: View {
    let item: ConversionItem

    var body: some View {
        HStack(spacing: 12) {
            statusIcon.frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.filename)
                        .lineLimit(1).truncationMode(.middle)
                        .font(.system(size: 13))
                    Text(item.ratio.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundStyle(Color.accentColor)
                }

                switch item.status {
                case .queued:
                    Text("Queued").font(.caption).foregroundStyle(.secondary)
                case .converting:
                    ProgressView(value: item.progress).progressViewStyle(.linear)
                case .done:
                    Text(item.outputURL?.lastPathComponent ?? "")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                case .failed(let msg):
                    Text(msg).font(.caption).foregroundStyle(.red)
                }
            }

            Spacer(minLength: 0)

            if case .converting = item.status {
                Text("\(Int(item.progress * 100))%")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            if case .done = item.status, let url = item.outputURL {
                Button {
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "arrow.right.circle").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    @ViewBuilder
    var statusIcon: some View {
        switch item.status {
        case .queued:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .converting:
            ProgressView().scaleEffect(0.7)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}

// MARK: - Bottom Bar

struct BottomBar: View {
    let converter: Converter
    let onAdd: () -> Void

    var doneCount: Int { converter.items.filter { $0.status == .done }.count }
    var hasFinished: Bool { converter.items.contains {
        switch $0.status { case .done, .failed: true; default: false }
    }}

    var body: some View {
        HStack {
            Button("+ Add Files", action: onAdd).buttonStyle(.bordered)
            Spacer()
            Text("\(doneCount) / \(converter.items.count) done")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Clear Finished") { converter.clearFinished() }
                .buttonStyle(.bordered).disabled(!hasFinished)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
