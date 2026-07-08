import Foundation
import AppKit

// MARK: - FFmpeg path resolution (shared across the app)

enum FFmpegLocator {
    static var appSupportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shortsify")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var installedPath: String? {
        let bundled = appSupportDir.appendingPathComponent("ffmpeg").path
        for path in [bundled, "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}

// MARK: - Installer

@MainActor
@Observable
final class FFmpegInstaller: NSObject {
    enum Phase: Equatable {
        case checking
        case ready
        case downloading(Double)   // 0.0 – 1.0
        case failed(String)
    }

    var phase: Phase = .checking

    // Download URL — static macOS build from evermeet.cx (LGPL, redistributable)
    private let downloadURL = URL(string: "https://evermeet.cx/ffmpeg/get/ffmpeg/zip")!
    private var downloadTask: URLSessionDownloadTask?

    func checkOrInstall() {
        if FFmpegLocator.installedPath != nil {
            phase = .ready
        } else {
            startDownload()
        }
    }

    func retry() { startDownload() }

    private func startDownload() {
        phase = .downloading(0)
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        downloadTask = session.downloadTask(with: downloadURL)
        downloadTask?.resume()
    }

    private func finishInstall(tempURL: URL) {
        let dest = FFmpegLocator.appSupportDir
        let ffmpegDest = dest.appendingPathComponent("ffmpeg")

        // Remove old copy if any
        try? FileManager.default.removeItem(at: ffmpegDest)

        // Unzip the downloaded archive
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-o", tempURL.path, "ffmpeg", "-d", dest.path]
        unzip.standardOutput = FileHandle.nullDevice
        unzip.standardError  = FileHandle.nullDevice

        do {
            try unzip.run()
            unzip.waitUntilExit()
        } catch {
            phase = .failed("Failed to unzip: \(error.localizedDescription)")
            return
        }

        guard FileManager.default.fileExists(atPath: ffmpegDest.path) else {
            phase = .failed("ffmpeg binary not found after unzip.")
            return
        }

        // Make executable
        try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                ofItemAtPath: ffmpegDest.path)

        phase = .ready
    }
}

// MARK: - URLSessionDownloadDelegate

extension FFmpegInstaller: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didWriteData _: Int64,
                                totalBytesWritten written: Int64,
                                totalBytesExpectedToWrite expected: Int64) {
        guard expected > 0 else { return }
        let progress = Double(written) / Double(expected)
        DispatchQueue.main.async { self.phase = .downloading(progress) }
    }

    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".zip")
        try? FileManager.default.moveItem(at: location, to: tmp)
        DispatchQueue.main.async { self.finishInstall(tempURL: tmp) }
    }

    nonisolated func urlSession(_ session: URLSession,
                                task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let error else { return }
        DispatchQueue.main.async {
            self.phase = .failed("Download failed: \(error.localizedDescription)")
        }
    }
}
