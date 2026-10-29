//
//  DriveManager.swift
//  Horizon
//
//  Created by Horizon on 29/10/26.
//

import AppKit
import Foundation
import Combine
import ServiceManagement

@MainActor
final class DriveManager: ObservableObject {
    static let shared = DriveManager()

    @Published var state: DriveState = .disconnected
    @Published var errorMessage: String? = nil
    @Published var accounts: [RemoteAccount] = []
    @Published var activeAccount: RemoteAccount? = nil

    // Authentication State
    @Published var isAuthenticating: Bool = false
    @Published var authStatusText: String = ""
    @Published var authError: String? = nil

    @Published var isLaunchAtLoginEnabled: Bool = false

    let appSupportDir: String
    let configPath: String
    let cacheDir: String
    let logFile: String
    let defaultMountPath: String

    private var currentProcess: Process?
    private var currentAuthProcess: Process?
    private var isUserInitiatedDisconnect = false

    private let onboardingKey = "hasCompletedOnboarding"

    var hasCompletedOnboarding: Bool {
        get {
            UserDefaults.standard.bool(forKey: onboardingKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: onboardingKey)
        }
    }

    var hasConfiguredAccounts: Bool {
        return !accounts.isEmpty
    }

    init() {
        self.defaultMountPath = (("~/GDrive" as NSString).expandingTildeInPath)
        self.appSupportDir = (("~/Library/Application Support/Horizon" as NSString).expandingTildeInPath)
        self.configPath = (("~/Library/Application Support/Horizon/rclone.conf" as NSString).expandingTildeInPath)
        self.cacheDir = (("~/Library/Caches/Horizon/rclone" as NSString).expandingTildeInPath)
        self.logFile = (("~/Library/Logs/Horizon/rclone.log" as NSString).expandingTildeInPath)

        // Ensure necessary directories exist
        try? FileManager.default.createDirectory(atPath: appSupportDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        let logDir = (logFile as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)

        // Check if there is an existing ~/.config/rclone/rclone.conf we should import if our config doesn't exist
        migrateDefaultConfigIfNeeded()

        // Check launch at login status
        if #available(macOS 13.0, *) {
            self.isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }

        // Load existing accounts
        loadAccountsSync()

        // Check if already mounted at startup
        if let active = activeAccount, Self.isPathMounted(active.mountPath) {
            self.state = .connected
        } else if Self.isPathMounted(defaultMountPath) {
            self.state = .connected
        }
    }

    private func migrateDefaultConfigIfNeeded() {
        if !FileManager.default.fileExists(atPath: configPath) {
            let legacyConfig = (("~/.config/rclone/rclone.conf" as NSString).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: legacyConfig) {
                try? FileManager.default.copyItem(atPath: legacyConfig, toPath: configPath)
            }
        }
    }

    // MARK: - Executable Finder

    nonisolated static func findRcloneExecutable() -> String? {
        // 1. Check bundled binary in all standard bundle locations
        if let auxURL = Bundle.main.url(forAuxiliaryExecutable: "rclone"),
           FileManager.default.isExecutableFile(atPath: auxURL.path) {
            return auxURL.path
        }

        if let bundlePath = Bundle.main.path(forResource: "rclone", ofType: nil),
           FileManager.default.isExecutableFile(atPath: bundlePath) {
            return bundlePath
        }

        if let resURL = Bundle.main.resourceURL?.appendingPathComponent("rclone"),
           FileManager.default.isExecutableFile(atPath: resURL.path) {
            return resURL.path
        }

        if let nestedResURL = Bundle.main.resourceURL?.appendingPathComponent("Resources/rclone"),
           FileManager.default.isExecutableFile(atPath: nestedResURL.path) {
            return nestedResURL.path
        }

        // 2. Check standard installation directories (development fallback)
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

    // MARK: - Account Management

    func refreshAccounts() {
        loadAccountsSync()
    }

    private func loadAccountsSync() {
        guard let rclone = Self.findRcloneExecutable() else { return }

        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: rclone)
        proc.arguments = ["config", "dump", "--config", configPath]
        proc.standardOutput = pipe

        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "")
        proc.environment = env

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
                var loaded: [RemoteAccount] = []
                for (name, props) in json {
                    let type = props["type"] as? String ?? "drive"
                    // Determine mount path
                    let mPath: String
                    if loaded.isEmpty {
                        mPath = defaultMountPath
                    } else {
                        mPath = (("~/GDrive-\(name)" as NSString).expandingTildeInPath)
                    }
                    let isMounted = Self.isPathMounted(mPath)
                    let account = RemoteAccount(
                        name: name,
                        provider: type,
                        accountName: props["account_name"] as? String,
                        accountEmail: props["account_email"] as? String,
                        mountPath: mPath,
                        isConnected: isMounted
                    )
                    loaded.append(account)
                }

                self.accounts = loaded
                if activeAccount == nil || !loaded.contains(where: { $0.name == activeAccount?.name }) {
                    self.activeAccount = loaded.first
                }

                // If any account is mounted, mark connected
                if loaded.contains(where: { $0.isConnected }) {
                    self.state = .connected
                }
            }
        } catch {
            print("Failed to load accounts: \(error)")
        }
    }

    // Fetch user info for a specific remote in the background
    func fetchUserInfo(for remoteName: String) async -> (email: String?, name: String?) {
        guard let rclone = Self.findRcloneExecutable() else { return (nil, nil) }

        return await Task.detached { [configPath] in
            let pipe = Pipe()
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: rclone)
            proc.arguments = ["config", "userinfo", "\(remoteName):", "--config", configPath, "--json"]
            proc.standardOutput = pipe

            var env = ProcessInfo.processInfo.environment
            let extraPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "")
            proc.environment = env

            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let email = (dict["email"] as? String) ?? (dict["user"] as? String)
                        let name = dict["name"] as? String
                        return (email, name)
                    }
                }
            } catch {}
            return (nil, nil)
        }.value
    }

    // MARK: - OAuth Setup Flow (Zero Keys Required)

    func startGoogleDriveConnection() async -> Bool {
        guard let rclone = Self.findRcloneExecutable() else {
            self.authError = "rclone executable was not found."
            return false
        }

        self.isAuthenticating = true
        self.authError = nil
        self.authStatusText = "Opening browser for Google authorization..."

        // Generate remote name (gdrive, gdrive2, etc.)
        let remoteName: String
        if accounts.contains(where: { $0.name == "gdrive" }) {
            var idx = 2
            while accounts.contains(where: { $0.name == "gdrive\(idx)" }) {
                idx += 1
            }
            remoteName = "gdrive\(idx)"
        } else {
            remoteName = "gdrive"
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: rclone)
        proc.arguments = [
            "config", "create",
            remoteName,
            "drive",
            "scope", "drive",
            "config_shared_client_id", "true",
            "--config", configPath
        ]

        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "")
        proc.environment = env

        let errPipe = Pipe()
        proc.standardError = errPipe

        self.currentAuthProcess = proc

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    try proc.run()
                    proc.waitUntilExit()

                    Task { @MainActor [weak self] in
                        guard let self = self else {
                            continuation.resume(returning: false)
                            return
                        }
                        self.currentAuthProcess = nil

                        if proc.terminationStatus == 0 {
                            self.authStatusText = "Authorization successful! Connecting drive..."

                            // Fetch user info for a nice display
                            let userInfo = await self.fetchUserInfo(for: remoteName)

                            self.refreshAccounts()
                            if var newlyAdded = self.accounts.first(where: { $0.name == remoteName }) {
                                newlyAdded.accountEmail = userInfo.email
                                newlyAdded.accountName = userInfo.name
                                self.activeAccount = newlyAdded
                            }

                            self.hasCompletedOnboarding = true
                            self.isAuthenticating = false

                            // Automatically mount the freshly connected drive!
                            self.connect()
                            continuation.resume(returning: true)
                        } else {
                            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                            let errString = String(data: errData, encoding: .utf8) ?? "Authentication process failed."
                            self.authError = errString.trimmingCharacters(in: .whitespacesAndNewlines)
                            self.isAuthenticating = false
                            continuation.resume(returning: false)
                        }
                    }
                } catch {
                    Task { @MainActor [weak self] in
                        self?.currentAuthProcess = nil
                        self?.authError = error.localizedDescription
                        self?.isAuthenticating = false
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    func cancelAuthentication() {
        currentAuthProcess?.terminate()
        currentAuthProcess = nil
        isAuthenticating = false
        authStatusText = ""
        authError = nil
    }

    // MARK: - Delete & Logout Connection

    func deleteAccount(_ account: RemoteAccount) async {
        // 1. If currently connected, disconnect first
        if state.isConnected || state == .connecting {
            disconnect()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        guard let rclone = Self.findRcloneExecutable() else { return }

        await Task.detached { [configPath] in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: rclone)
            proc.arguments = ["config", "delete", account.name, "--config", configPath]

            var env = ProcessInfo.processInfo.environment
            let extraPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "")
            proc.environment = env

            try? proc.run()
            proc.waitUntilExit()
        }.value

        refreshAccounts()

        if accounts.isEmpty {
            hasCompletedOnboarding = false
            activeAccount = nil
            state = .disconnected
        }
    }

    func logoutAccount(_ account: RemoteAccount) async {
        if state.isConnected || state == .connecting {
            disconnect()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        guard let rclone = Self.findRcloneExecutable() else { return }

        await Task.detached { [configPath] in
            // Revoke oauth token
            let procDisconnect = Process()
            procDisconnect.executableURL = URL(fileURLWithPath: rclone)
            procDisconnect.arguments = ["config", "disconnect", "\(account.name):", "--config", configPath]

            var env = ProcessInfo.processInfo.environment
            let extraPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "")
            procDisconnect.environment = env

            try? procDisconnect.run()
            procDisconnect.waitUntilExit()

            // Delete remote
            let procDelete = Process()
            procDelete.executableURL = URL(fileURLWithPath: rclone)
            procDelete.arguments = ["config", "delete", account.name, "--config", configPath]
            procDelete.environment = env
            try? procDelete.run()
            procDelete.waitUntilExit()
        }.value

        refreshAccounts()

        if accounts.isEmpty {
            hasCompletedOnboarding = false
            activeAccount = nil
            state = .disconnected
        }
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

    var activeMountPath: String {
        activeAccount?.mountPath ?? defaultMountPath
    }

    var activeRemoteName: String {
        activeAccount?.name ?? "gdrive"
    }

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
            let err = "rclone executable was not found."
            state = .error(err)
            errorMessage = err
            return
        }

        let mountPath = self.activeMountPath
        let remoteName = self.activeRemoteName

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
            "\(remoteName):",
            mountPath,
            "--config", configPath,
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
                self.updateAccountsMountStatus()
            }
        }

        do {
            try process.run()
            self.currentProcess = process
        } catch {
            let err = "Failed to launch rclone process: \(error.localizedDescription)"
            self.state = .error(err)
            errorMessage = err
            return
        }

        // Poll for mount readiness
        Task {
            let startTime = Date()
            var isMounted = false

            while Date().timeIntervalSince(startTime) < 15.0 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s check interval
                if Self.isPathMounted(mountPath) {
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
                self.updateAccountsMountStatus()
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
        let mountLocation = self.activeMountPath

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
            self.updateAccountsMountStatus()
        }
    }

    private func updateAccountsMountStatus() {
        for idx in accounts.indices {
            accounts[idx].isConnected = Self.isPathMounted(accounts[idx].mountPath)
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
        killProc.arguments = ["-9", "-f", "rclone nfsmount"]
        try? killProc.run()
        killProc.waitUntilExit()
    }

    // MARK: - Launch at Login

    func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    isLaunchAtLoginEnabled = false
                } else {
                    try SMAppService.mainApp.register()
                    isLaunchAtLoginEnabled = true
                }
            } catch {
                print("Failed to toggle launch at login: \(error)")
            }
        }
    }

    // MARK: - Shortcuts

    func openInFinder() {
        let url = URL(fileURLWithPath: activeMountPath)
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

    func clearCache() {
        if state.isConnected {
            disconnect()
        }
        try? FileManager.default.removeItem(atPath: cacheDir)
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
    }
}
