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

    // Overall / Aggregate State
    @Published var state: DriveState = .disconnected
    @Published var errorMessage: String? = nil
    @Published var accounts: [RemoteAccount] = []
    @Published var activeAccount: RemoteAccount? = nil

    // Multi-Account Independent States
    @Published var accountStates: [String: DriveState] = [:] // keyed by account.id
    @Published var accountSyncing: [String: Bool] = [:]      // keyed by account.id
    @Published var accountLastSync: [String: Date] = [:]     // keyed by account.id

    // Authentication State
    @Published var isAuthenticating: Bool = false
    @Published var authStatusText: String = ""
    @Published var authError: String? = nil

    @Published var isLaunchAtLoginEnabled: Bool = false

    // Aggregate Two-Way Sync
    @Published var isSyncing: Bool = false
    @Published var lastSyncTime: Date? = nil

    var formattedLastSync: String {
        guard let lastSync = lastSyncTime else { return "Ready to sync" }
        let interval = Date().timeIntervalSince(lastSync)
        if interval < 10 {
            return "Synced just now"
        } else if interval < 60 {
            return "Synced \(Int(interval))s ago"
        } else {
            let minutes = Int(interval / 60)
            return "Synced \(minutes)m ago"
        }
    }

    private var syncTask: Task<Void, Never>? = nil

    let appSupportDir: String
    let configPath: String
    let cacheDir: String
    let logFile: String
    let defaultMountPath: String

    // Multi-Process Tracking
    private var runningProcesses: [String: Process] = [:] // keyed by account.id
    private var accountRcPorts: [String: Int] = [:]       // unique RC port per account
    private var userInitiatedDisconnects: Set<String> = []
    private var currentAuthProcess: Process?

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

    var connectedCount: Int {
        return accounts.filter { stateForAccount($0) == .connected }.count
    }

    init() {
        self.defaultMountPath = (("~/GDrive" as NSString).expandingTildeInPath)
        self.appSupportDir = (("~/Library/Application Support/Horizon" as NSString).expandingTildeInPath)
        self.configPath = (("~/Library/Application Support/Horizon/rclone.conf" as NSString).expandingTildeInPath)
        self.cacheDir = (("~/Library/Caches/Horizon/rclone" as NSString).expandingTildeInPath)
        self.logFile = (("~/Library/Logs/Horizon/rclone.log" as NSString).expandingTildeInPath)

        // Ensure necessary base directories exist
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

        // Initialize SQLite and load accounts
        loadAccountsSync()
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

        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in pathEnv.components(separatedBy: ":") where !dir.isEmpty {
            let fullPath = (dir as NSString).appendingPathComponent("rclone")
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }

        return nil
    }

    // MARK: - Account Management (SQLite Backed)

    func refreshAccounts() {
        loadAccountsSync()
    }

    private func loadAccountsSync() {
        // 1. Fetch from SQLite Database
        var dbAccounts = AccountDatabase.shared.getAllAccounts()

        // 2. Discover remotes in rclone.conf (for automatic migration on first launch)
        let configRemotes = fetchRcloneConfigRemotes()

        for (remoteName, props) in configRemotes {
            if !dbAccounts.contains(where: { $0.name == remoteName }) {
                let type = props["type"] as? String ?? "drive"
                let displayName: String
                let mountPath: String
                if remoteName == "gdrive" {
                    displayName = "Google Drive"
                    mountPath = defaultMountPath
                } else {
                    displayName = remoteName.replacingOccurrences(of: "_", with: " ").capitalized
                    mountPath = (("~/\(displayName)" as NSString).expandingTildeInPath)
                }

                let newAcc = RemoteAccount(
                    name: remoteName,
                    displayName: displayName,
                    provider: type,
                    accountName: displayName,
                    accountEmail: nil,
                    mountPath: mountPath,
                    isConnected: Self.isPathMounted(mountPath),
                    autoConnect: true,
                    createdAt: Date()
                )
                AccountDatabase.shared.saveAccount(newAcc)
                dbAccounts.append(newAcc)
            }
        }

        // 3. Check mount states for all accounts
        for i in dbAccounts.indices {
            let isMounted = Self.isPathMounted(dbAccounts[i].mountPath)
            dbAccounts[i].isConnected = isMounted
            accountStates[dbAccounts[i].id] = isMounted ? .connected : .disconnected
        }

        self.accounts = dbAccounts
        if activeAccount == nil || !dbAccounts.contains(where: { $0.id == activeAccount?.id }) {
            self.activeAccount = dbAccounts.first
        }

        updateOverallState()
    }

    private func fetchRcloneConfigRemotes() -> [String: [String: Any]] {
        guard let rclone = Self.findRcloneExecutable() else { return [:] }
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
                return json
            }
        } catch {}
        return [:]
    }

    func stateForAccount(_ account: RemoteAccount) -> DriveState {
        return accountStates[account.id] ?? (account.isConnected ? .connected : .disconnected)
    }

    func isAccountSyncing(_ account: RemoteAccount) -> Bool {
        return accountSyncing[account.id] ?? false
    }

    func formattedLastSync(for account: RemoteAccount) -> String {
        guard let lastSync = accountLastSync[account.id] else {
            return "Ready to sync"
        }
        let interval = Date().timeIntervalSince(lastSync)
        if interval < 10 {
            return "Synced just now"
        } else if interval < 60 {
            return "Synced \(Int(interval))s ago"
        } else {
            let minutes = Int(interval / 60)
            return "Synced \(minutes)m ago"
        }
    }

    // MARK: - Sanitizer & Port Management

    nonisolated static func sanitizeRemoteName(_ name: String) -> String {
        let cleaned = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        return cleaned.isEmpty ? "cloud_drive" : cleaned
    }

    private func allocateRcPort(for accountId: String) -> Int {
        if let existing = accountRcPorts[accountId] {
            return existing
        }
        var port = 5572
        let usedPorts = Set(accountRcPorts.values)
        while usedPorts.contains(port) {
            port += 1
        }
        accountRcPorts[accountId] = port
        return port
    }

    // MARK: - Connection Flow (User Names Connection & Folder)

    func startGoogleDriveConnection() async -> Bool {
        return await startConnection(
            displayName: "Google Drive",
            mountPath: defaultMountPath,
            provider: "drive"
        )
    }

    func startConnection(displayName: String, mountPath: String, provider: String = "drive") async -> Bool {
        guard let rclone = Self.findRcloneExecutable() else {
            self.authError = "rclone executable was not found."
            return false
        }

        self.isAuthenticating = true
        self.authError = nil
        self.authStatusText = "Opening browser for \(provider.capitalized) authorization..."

        // Generate sanitized remote name based on user-assigned displayName
        let baseRemote = Self.sanitizeRemoteName(displayName)
        var remoteName = baseRemote
        var counter = 2
        while accounts.contains(where: { $0.name == remoteName }) {
            remoteName = "\(baseRemote)_\(counter)"
            counter += 1
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: rclone)
        proc.arguments = [
            "config", "create",
            remoteName,
            provider,
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
        proc.standardOutput = FileHandle.nullDevice

        let errHandle = errPipe.fileHandleForReading
        var capturedStderr = ""
        let syncQueue = DispatchQueue(label: "horizon.auth.stderr")
        errHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                syncQueue.sync {
                    capturedStderr += str
                }
            }
        }

        self.currentAuthProcess = proc

        let (exitCode, didRun) = await Task.detached { () -> (Int32, Bool) in
            do {
                try proc.run()
                proc.waitUntilExit()
                return (proc.terminationStatus, true)
            } catch {
                return (-1, false)
            }
        }.value

        errHandle.readabilityHandler = nil
        self.currentAuthProcess = nil

        if didRun && exitCode == 0 {
            self.authStatusText = "Authorization successful! Connecting drive..."

            let resolvedMountPath = (mountPath as NSString).expandingTildeInPath
            try? FileManager.default.createDirectory(atPath: resolvedMountPath, withIntermediateDirectories: true)

            let newAccount = RemoteAccount(
                name: remoteName,
                displayName: displayName,
                provider: provider,
                accountName: displayName,
                accountEmail: nil,
                mountPath: resolvedMountPath,
                isConnected: false,
                autoConnect: true,
                createdAt: Date()
            )

            // Persist into SQLite
            AccountDatabase.shared.saveAccount(newAccount)

            self.accounts.append(newAccount)
            self.activeAccount = newAccount
            self.hasCompletedOnboarding = true
            self.isAuthenticating = false

            // Automatically mount the newly created connection immediately alongside others!
            self.connectAccount(newAccount)
            return true
        } else {
            var errorText = ""
            syncQueue.sync {
                errorText = capturedStderr.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            self.authError = errorText.isEmpty ? "Authentication failed or was cancelled." : errorText
            self.isAuthenticating = false
            return false
        }
    }

    func cancelAuthentication() {
        currentAuthProcess?.terminate()
        currentAuthProcess = nil
        isAuthenticating = false
        authStatusText = ""
        authError = nil
    }

    // MARK: - Multi-Mount Connect & Disconnect

    func connectAccount(_ account: RemoteAccount) {
        guard let rcloneExecutable = Self.findRcloneExecutable() else {
            accountStates[account.id] = .error("rclone executable not found")
            updateOverallState()
            return
        }

        if Self.isPathMounted(account.mountPath) {
            accountStates[account.id] = .connected
            updateAccountConnection(id: account.id, isConnected: true)
            updateOverallState()
            return
        }

        accountStates[account.id] = .connecting
        updateOverallState()

        let mountPath = account.mountPath
        try? FileManager.default.createDirectory(atPath: mountPath, withIntermediateDirectories: true)

        let accountCache = (cacheDir as NSString).appendingPathComponent(account.name)
        try? FileManager.default.createDirectory(atPath: accountCache, withIntermediateDirectories: true)

        let nfsCacheDir = (accountCache as NSString).appendingPathComponent("nfs-handles")
        try? FileManager.default.createDirectory(atPath: nfsCacheDir, withIntermediateDirectories: true)

        let accountLog = ((logFile as NSString).deletingLastPathComponent as NSString).appendingPathComponent("rclone-\(account.name).log")

        let rcPort = allocateRcPort(for: account.id)

        let arguments = [
            "nfsmount",
            "\(account.name):",
            mountPath,
            "--config", configPath,
            "--volname", account.displayName,
            "--vfs-cache-mode", "full",
            "--cache-dir", accountCache,
            "--vfs-cache-max-size", "50G",
            "--vfs-cache-max-age", "24h",
            // Multi-stream parallel reads & responsive chunking: 4 concurrent connections prevent macOS NFS timeouts
            "--vfs-read-chunk-streams", "4",
            "--vfs-read-chunk-size", "8M",
            "--vfs-read-chunk-size-limit", "off",
            "--vfs-read-wait", "20ms",
            "--vfs-read-ahead", "128M",
            "--buffer-size", "32M",
            "--vfs-write-back", "5s",
            // Instant folder browsing without background poll drops
            "--dir-cache-time", "72h",
            "--poll-interval", "0",
            // Google Drive tuning: fast API pacing and upload chunk size
            "--drive-chunk-size", "64M",
            "--drive-pacer-min-sleep", "10ms",
            "--drive-pacer-burst", "200",
            "--drive-export-formats", "webloc",
            // Proven Stage 1 disk-backed NFS handle cache
            "--nfs-cache-type", "disk",
            // RC API & Logs
            "--rc",
            "--rc-addr", "127.0.0.1:\(rcPort)",
            "--rc-user", "app",
            "--rc-pass", "secret123",
            "--log-file", accountLog,
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

        let accountId = account.id

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.runningProcesses.removeValue(forKey: accountId)
                self.accountRcPorts.removeValue(forKey: accountId)
                if self.userInitiatedDisconnects.contains(accountId) {
                    self.accountStates[accountId] = .disconnected
                    self.userInitiatedDisconnects.remove(accountId)
                } else {
                    let code = proc.terminationStatus
                    let err = "Exited unexpectedly with code \(code)"
                    self.accountStates[accountId] = .error(err)
                }
                self.updateAccountConnection(id: accountId, isConnected: false)
                self.updateOverallState()
            }
        }

        do {
            try process.run()
            runningProcesses[account.id] = process
        } catch {
            let err = "Failed to launch process: \(error.localizedDescription)"
            accountStates[account.id] = .error(err)
            updateOverallState()
            return
        }

        // Readiness poll
        Task {
            let startTime = Date()
            var isMounted = false

            while Date().timeIntervalSince(startTime) < 15.0 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Self.isPathMounted(mountPath) {
                    isMounted = true
                    break
                }
                if process.isRunning == false {
                    break
                }
            }

            if isMounted && process.isRunning {
                self.accountStates[accountId] = .connected
                self.updateAccountConnection(id: accountId, isConnected: true)
                self.updateOverallState()
            } else {
                let err = "Mount timed out or failed to mount."
                self.accountStates[accountId] = .error(err)
                self.updateOverallState()
                self.disconnectAccount(account)
            }
        }
    }

    func disconnectAccount(_ account: RemoteAccount) {
        let accountId = account.id
        userInitiatedDisconnects.insert(accountId)
        accountStates[accountId] = .disconnecting
        updateOverallState()

        let proc = runningProcesses.removeValue(forKey: accountId)
        accountRcPorts.removeValue(forKey: accountId)
        let mountLocation = account.mountPath

        Task.detached(priority: .userInitiated) { [weak self] in
            // 1. Unmount volume FIRST while rclone is still alive
            Self.unmountVolume(path: mountLocation)

            // 2. Terminate rclone process
            if let proc = proc, proc.isRunning {
                proc.terminate()
                var wait = 0
                while proc.isRunning && wait < 15 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    wait += 1
                }
                if proc.isRunning {
                    proc.interrupt()
                }
            }

            // 3. Clean up any stray rclone nfsmount on this path
            let pkill = Process()
            pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            pkill.arguments = ["-f", "rclone nfsmount.*\(mountLocation)"]
            pkill.standardOutput = FileHandle.nullDevice
            pkill.standardError = FileHandle.nullDevice
            try? pkill.run()
            pkill.waitUntilExit()

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.accountStates[accountId] = .disconnected
                self.userInitiatedDisconnects.remove(accountId)
                self.updateAccountConnection(id: accountId, isConnected: false)
                self.updateOverallState()
            }
        }
    }

    func toggleAccountConnection(_ account: RemoteAccount) {
        let current = stateForAccount(account)
        if current.isConnected || current == .connecting {
            disconnectAccount(account)
        } else {
            connectAccount(account)
        }
    }

    private func updateAccountConnection(id: String, isConnected: Bool) {
        if let idx = accounts.firstIndex(where: { $0.id == id }) {
            accounts[idx].isConnected = isConnected
        }
        AccountDatabase.shared.updateConnectionStatus(id: id, isConnected: isConnected)
    }

    func updateOverallState() {
        let hasConnecting = accountStates.values.contains(.connecting)
        let hasConnected = accountStates.values.contains(.connected)
        let hasError = accountStates.values.contains { state in
            if case .error = state { return true }
            return false
        }

        if hasConnecting {
            self.state = .connecting
        } else if hasConnected {
            self.state = .connected
        } else if hasError {
            self.state = .error("One or more drives encountered an issue")
        } else {
            self.state = .disconnected
        }
    }

    // MARK: - Global Connect / Disconnect (Backwards Compatibility)

    var activeMountPath: String {
        activeAccount?.mountPath ?? defaultMountPath
    }

    func toggleConnection() {
        if state.isConnected {
            disconnect()
        } else {
            connect()
        }
    }

    func connect() {
        if let active = activeAccount {
            connectAccount(active)
        } else if let first = accounts.first {
            connectAccount(first)
        }
    }

    func disconnect() {
        for account in accounts where stateForAccount(account).isConnected {
            disconnectAccount(account)
        }
    }

    func disconnectSync() {
        for account in accounts {
            Self.unmountVolume(path: account.mountPath)
            if let proc = runningProcesses[account.id], proc.isRunning {
                proc.terminate()
            }
        }
        runningProcesses.removeAll()
    }

    // MARK: - Delete & Logout Connection

    func deleteAccount(_ account: RemoteAccount) async {
        disconnectAccount(account)
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Remove from rclone config
        if let rclone = Self.findRcloneExecutable() {
            await Task.detached { [configPath] in
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: rclone)
                proc.arguments = ["config", "delete", account.name, "--config", configPath]
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
                try? proc.run()
                proc.waitUntilExit()
            }.value
        }

        // Remove from SQLite Database
        AccountDatabase.shared.deleteAccount(id: account.id)

        // Remove from memory
        accounts.removeAll { $0.id == account.id }
        accountStates.removeValue(forKey: account.id)
        accountRcPorts.removeValue(forKey: account.id)

        if activeAccount?.id == account.id {
            activeAccount = accounts.first
        }
        updateOverallState()

        if accounts.isEmpty {
            hasCompletedOnboarding = false
            state = .disconnected
        }
    }

    func logoutAccount(_ account: RemoteAccount) async {
        disconnectAccount(account)
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        guard let rclone = Self.findRcloneExecutable() else { return }

        await Task.detached { [configPath] in
            let procDisconnect = Process()
            procDisconnect.executableURL = URL(fileURLWithPath: rclone)
            procDisconnect.arguments = ["config", "disconnect", "\(account.name):", "--config", configPath]
            procDisconnect.standardOutput = FileHandle.nullDevice
            procDisconnect.standardError = FileHandle.nullDevice
            try? procDisconnect.run()
            procDisconnect.waitUntilExit()

            let procDelete = Process()
            procDelete.executableURL = URL(fileURLWithPath: rclone)
            procDelete.arguments = ["config", "delete", account.name, "--config", configPath]
            procDelete.standardOutput = FileHandle.nullDevice
            procDelete.standardError = FileHandle.nullDevice
            try? procDelete.run()
            procDelete.waitUntilExit()
        }.value

        AccountDatabase.shared.deleteAccount(id: account.id)
        accounts.removeAll { $0.id == account.id }
        accountStates.removeValue(forKey: account.id)
        accountRcPorts.removeValue(forKey: account.id)

        if activeAccount?.id == account.id {
            activeAccount = accounts.first
        }
        updateOverallState()

        if accounts.isEmpty {
            hasCompletedOnboarding = false
            state = .disconnected
        }
    }

    // MARK: - Mount Checks & Control

    nonisolated static func isPathMounted(_ targetPath: String) -> Bool {
        let standardized = URL(fileURLWithPath: targetPath).standardized.path

        var mntbuf: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&mntbuf, MNT_NOWAIT)
        if count > 0, let buf = mntbuf {
            for i in 0..<Int(count) {
                var stat = buf[i]
                let mountedPath = withUnsafePointer(to: &stat.f_mntonname) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                        String(cString: $0)
                    }
                }
                if mountedPath == standardized {
                    return true
                }
            }
        }
        return false
    }

    nonisolated static func unmountVolume(path: String) {
        let standardized = URL(fileURLWithPath: path).standardized.path

        // 1. Polite clean unmount first so macOS NetAuthSysAgent doesn't trigger "Server connections interrupted"
        let pClean = Process()
        pClean.executableURL = URL(fileURLWithPath: "/sbin/umount")
        pClean.arguments = [standardized]
        pClean.standardOutput = FileHandle.nullDevice
        pClean.standardError = FileHandle.nullDevice
        try? pClean.run()
        pClean.waitUntilExit()

        // 2. Only if still mounted after polite unmount, use force unmount
        if isPathMounted(standardized) {
            let pForce = Process()
            pForce.executableURL = URL(fileURLWithPath: "/sbin/umount")
            pForce.arguments = ["-f", standardized]
            pForce.standardOutput = FileHandle.nullDevice
            pForce.standardError = FileHandle.nullDevice
            try? pForce.run()
            pForce.waitUntilExit()
        }
    }

    nonisolated static func forceUnmount(path: String) {
        unmountVolume(path: path)
    }

    nonisolated static func unmount(path: String) {
        unmountVolume(path: path)
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
        if let active = activeAccount {
            openAccountInFinder(active)
        } else {
            let url = URL(fileURLWithPath: activeMountPath)
            NSWorkspace.shared.open(url)
        }
    }

    func openAccountInFinder(_ account: RemoteAccount) {
        let url = URL(fileURLWithPath: account.mountPath)
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
        disconnect()
        try? FileManager.default.removeItem(atPath: cacheDir)
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - On-Demand Refresh
    func startPeriodicSync() {
        // Disabled: Cloud drive is not updated often from outside, avoiding periodic cache/NFS churn
    }

    func stopPeriodicSync() {
        syncTask?.cancel()
        syncTask = nil
    }

    func syncNow() {
        for account in accounts where stateForAccount(account) == .connected {
            syncAccount(account, forceRefresh: true)
        }
    }

    func syncAccount(_ account: RemoteAccount, forceRefresh: Bool = true) {
        Task {
            await syncAccountAsync(account, forceRefresh: forceRefresh)
        }
    }

    private func syncAccountAsync(_ account: RemoteAccount, forceRefresh: Bool = false) async {
        let accountId = account.id
        guard stateForAccount(account) == .connected else { return }

        await MainActor.run {
            self.accountSyncing[accountId] = true
            self.isSyncing = true
        }

        // Only invoke rclone RC vfs/refresh if explicitly requested
        if forceRefresh,
           let proc = runningProcesses[accountId], proc.isRunning,
           let port = accountRcPorts[accountId],
           let url = URL(string: "http://127.0.0.1:\(port)/vfs/refresh") {

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = "{\"_async\":true}".data(using: .utf8)
            let authString = "app:secret123"
            if let authData = authString.data(using: .utf8) {
                request.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }

            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 2
            config.timeoutIntervalForResource = 2
            config.waitsForConnectivity = false
            let session = URLSession(configuration: config)

            _ = try? await session.data(for: request)
        }

        await MainActor.run {
            self.accountSyncing[accountId] = false
            self.accountLastSync[accountId] = Date()
            self.lastSyncTime = Date()
            self.isSyncing = self.accountSyncing.values.contains(true)
        }
    }

    nonisolated static func notifyFinder(path: String) {
        // No-op: Do not trigger AppleScript window updates to avoid invalidating active NFS file handles
    }
}
