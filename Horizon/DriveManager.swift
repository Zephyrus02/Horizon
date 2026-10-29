//
//  DriveManager.swift
//  Horizon
//
//  Created by Horizon on 29/10/26.
//

import AppKit
import Foundation
import Combine

@MainActor
final class DriveManager: ObservableObject {
    static let shared = DriveManager()

    @Published var state: DriveState = .disconnected
    @Published var errorMessage: String? = nil

    let mountPath: String
    let cacheDir: String
    let logFile: String

    private var currentProcess: Process?
    private var isUserInitiatedDisconnect = false

    init() {
        self.mountPath = (("~/GDrive" as NSString).expandingTildeInPath)
        self.cacheDir = (("~/Library/Caches/Horizon/rclone" as NSString).expandingTildeInPath)
        self.logFile = (("~/Library/Logs/Horizon/rclone.log" as NSString).expandingTildeInPath)

        // Check if already mounted at startup
        if Self.isPathMounted(self.mountPath) {
            self.state = .connected
        }
    }

    // MARK: - Executable Finder

    nonisolated static func findRcloneExecutable() -> String? {
        // 1. Check bundled binary inside app resources
        if let bundlePath = Bundle.main.path(forResource: "rclone", ofType: nil),
           FileManager.default.isExecutableFile(atPath: bundlePath) {
            return bundlePath
        }

        // 2. Check standard installation directories
        let commonPaths = [
            "/opt/homebrew/bin/rclone",
            "/usr/local/bin/rclone",
            "/usr/bin/rclone",
            "/bin/rclone"
        ]

        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // 3. Search via environment PATH
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in pathEnv.components(separatedBy: ":") where !dir.isEmpty {
            let fullPath = (dir as NSString).appendingPathComponent("rclone")
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }

        return nil
    }

    // MARK: - Mount Checks & Control

    nonisolated static func isPathMounted(_ targetPath: String) -> Bool {
        let standardized = URL(fileURLWithPath: targetPath).standardized.path

        // Check 1: statfs
        var stat = statfs()
        if statfs(standardized, &stat) == 0 {
            let mountedPath = withUnsafePointer(to: &stat.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                    String(cString: $0)
                }
            }
            if mountedPath == standardized {
                return true
            }
        }

        // Check 2: /sbin/mount output
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount")
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output.contains(" on \(standardized) (")
            }
        } catch {
            return false
        }

        return false
    }

    nonisolated static func forceUnmount(path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/umount")
        process.arguments = ["-f", path]
        try? process.run()
        process.waitUntilExit()
    }

    nonisolated static func unmount(path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/umount")
        process.arguments = [path]
        try? process.run()
        process.waitUntilExit()

        if isPathMounted(path) {
            forceUnmount(path: path)
        }
    }

    // MARK: - Connect & Disconnect

    func toggleConnection() {
        if state.isConnected {
            disconnect()
        } else {
            connect()
        }
    }

    func connect() {
        guard state == .disconnected || state.isError else {
            return
        }

        state = .connecting
        errorMessage = nil
        isUserInitiatedDisconnect = false

        guard let rcloneExecutable = Self.findRcloneExecutable() else {
            let err = "rclone executable was not found. Please ensure rclone is installed (e.g. via Homebrew)."
            state = .error(err)
            errorMessage = err
            return
        }

        // Ensure target directories exist
        let logDir = (logFile as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: mountPath, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        } catch {
            let err = "Failed to create directories: \(error.localizedDescription)"
            state = .error(err)
            errorMessage = err
            return
        }

        // Clean up any stale mount at the destination before starting
        if Self.isPathMounted(mountPath) {
            Self.forceUnmount(path: mountPath)
        }

        let arguments = [
            "nfsmount",
            "gdrive:",
            mountPath,
            "--volname", "Google Drive",
            "--vfs-cache-mode", "full",
            "--cache-dir", cacheDir,
            "--vfs-cache-max-size", "20G",
            "--vfs-cache-max-age", "24h",
            "--vfs-read-ahead", "256M",
            "--vfs-write-back", "5s",
            "--dir-cache-time", "5m",
            "--poll-interval", "30s",
            "--buffer-size", "64M",
            "--drive-chunk-size", "64M",
            "--drive-export-formats", "webloc",
            "--nfs-cache-type", "disk",
            "--rc",
            "--rc-addr", "127.0.0.1:5572",
            "--rc-user", "app",
            "--rc-pass", "secret123",
            "--log-file", logFile,
            "--log-level", "INFO"
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: rcloneExecutable)
        process.arguments = arguments

        // Ensure PATH environment covers Homebrew & standard paths
        var environment = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existing = environment["PATH"], !existing.isEmpty {
            environment["PATH"] = extraPaths + ":" + existing
        } else {
            environment["PATH"] = extraPaths
        }
        process.environment = environment

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.isUserInitiatedDisconnect {
                    self.state = .disconnected
                    self.isUserInitiatedDisconnect = false
                } else if self.state == .connected || self.state == .connecting {
                    let code = proc.terminationStatus
                    let err = "rclone exited unexpectedly with code \(code)"
                    self.state = .error(err)
                    self.errorMessage = err
                }
                self.currentProcess = nil
            }
        }

        do {
            try process.run()
            self.currentProcess = process
        } catch {
            let err = "Failed to launch rclone process: \(error.localizedDescription)"
            self.state = .error(err)
            self.errorMessage = err
            return
        }

        // Poll for mount readiness
        Task {
            let startTime = Date()
            var isMounted = false

            while Date().timeIntervalSince(startTime) < 15.0 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s check interval
                if Self.isPathMounted(self.mountPath) {
                    isMounted = true
                    break
                }
                if self.currentProcess?.isRunning == false {
                    break
                }
            }

            if isMounted && self.currentProcess?.isRunning == true {
                self.state = .connected
                self.errorMessage = nil
            } else if self.state == .connecting {
                let err = "Mount timed out or rclone failed to mount."
                self.state = .error(err)
                self.errorMessage = err
                self.disconnect()
            }
        }
    }

    func disconnect() {
        guard state != .disconnected && state != .disconnecting else {
            return
        }

        state = .disconnecting
        isUserInitiatedDisconnect = true

        let proc = self.currentProcess
        let mountLocation = self.mountPath

        Task {
            if let proc = proc, proc.isRunning {
                proc.terminate()
            }

            Self.unmount(path: mountLocation)

            var waitTime = 0.0
            while (proc?.isRunning == true) && waitTime < 3.0 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                waitTime += 0.2
            }

            if proc?.isRunning == true {
                proc?.interrupt()
            }

            if Self.isPathMounted(mountLocation) {
                Self.forceUnmount(path: mountLocation)
            }

            self.currentProcess = nil
            self.state = .disconnected
            self.isUserInitiatedDisconnect = false
        }
    }

    // Synchronous unmount used when quitting the application
    nonisolated func disconnectSync() {
        let standardizedMount = URL(fileURLWithPath: (("~/GDrive" as NSString).expandingTildeInPath)).standardized.path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/sbin/umount")
        p.arguments = ["-f", standardizedMount]
        try? p.run()
        p.waitUntilExit()

        let killProc = Process()
        killProc.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killProc.arguments = ["-9", "-f", "rclone nfsmount gdrive:"]
        try? killProc.run()
        killProc.waitUntilExit()
    }

    // MARK: - Shortcuts

    func openInFinder() {
        let url = URL(fileURLWithPath: mountPath)
        NSWorkspace.shared.open(url)
    }

    func openLogs() {
        let url = URL(fileURLWithPath: logFile)
        if FileManager.default.fileExists(atPath: logFile) {
            NSWorkspace.shared.open(url)
        } else {
            let logDir = url.deletingLastPathComponent()
            NSWorkspace.shared.open(logDir)
        }
    }
}

