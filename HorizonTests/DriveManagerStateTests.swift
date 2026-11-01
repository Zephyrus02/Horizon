//
//  DriveManagerStateTests.swift
//  HorizonTests
//
//  Initialisation, account loading/migration, derived state, shortcuts and settings.
//

import Testing
import Foundation
@testable import Horizon

@MainActor
@Suite("DriveManager – state & loading")
struct DriveManagerStateTests {

    // MARK: Static helpers

    @Test("sanitizeRemoteName", arguments: [
        ("Work Drive", "work_drive"),
        ("Personal & School Drive", "personal_school_drive"),
        ("My-Storage_123", "my-storage_123"),
        ("", "cloud_drive"),
        ("   ", "cloud_drive"),
        ("!!!", "cloud_drive"),
        ("__lead and trail__", "lead_and_trail"),
        ("--dashes--", "dashes"),
        ("UPPER Case", "upper_case"),
        ("a    b", "a_b"),
        ("Dropbox (Work)", "dropbox_work"),
        ("日本語", "日本語"),
    ])
    func sanitizeRemoteName(input: String, expected: String) {
        #expect(DriveManager.sanitizeRemoteName(input) == expected)
    }

    @Test func isPathMountedRecognisesRootAndRejectsPlainDirectories() throws {
        #expect(DriveManager.isPathMounted("/"))
        #expect(DriveManager.isPathMounted("/./"))            // standardised before comparing
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(!DriveManager.isPathMounted(dir.path))
        #expect(!DriveManager.isPathMounted("/definitely/not/a/mount/\(UUID().uuidString)"))
    }

    @Test func unmountHelpersAreSafeOnUnmountedPaths() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        DriveManager.unmountVolume(path: dir.path)
        DriveManager.forceUnmount(path: dir.path)
        DriveManager.unmount(path: dir.path)
        DriveManager.notifyFinder(path: dir.path)
        #expect(FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func findRcloneExecutableReturnsExecutableOrNil() {
        if let path = DriveManager.findRcloneExecutable() {
            #expect(FileManager.default.isExecutableFile(atPath: path))
            #expect(path.hasSuffix("rclone"))
        }
    }

    // MARK: Initialisation

    @Test func initCreatesDirectoriesAndDerivesPaths() async throws {
        try await withHarness { h in
            let m = h.manager
            #expect(m.appSupportDir == h.appSupportDir)
            #expect(m.configPath == h.configPath)
            #expect(m.cacheDir == h.cacheDir)
            #expect(m.logFile == h.logFile)
            #expect(m.defaultMountPath == h.defaultMountPath)
            #expect(m.activeMountPath == h.defaultMountPath)

            var isDir: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: h.appSupportDir, isDirectory: &isDir) && isDir.boolValue)
            #expect(FileManager.default.fileExists(atPath: h.cacheDir, isDirectory: &isDir) && isDir.boolValue)
            let logDir = (h.logFile as NSString).deletingLastPathComponent
            #expect(FileManager.default.fileExists(atPath: logDir, isDirectory: &isDir) && isDir.boolValue)
        }
    }

    @Test func freshManagerHasDisconnectedIdleDefaults() async throws {
        try await withHarness { h in
            let m = h.manager
            #expect(m.state == .disconnected)
            #expect(m.accounts.isEmpty)
            #expect(m.activeAccount == nil)
            #expect(m.errorMessage == nil)
            #expect(!m.isAuthenticating)
            #expect(m.authError == nil)
            #expect(m.authStatusText.isEmpty)
            #expect(!m.isSyncing)
            #expect(m.lastSyncTime == nil)
            #expect(!m.hasConfiguredAccounts)
            #expect(m.connectedCount == 0)
        }
    }

    @Test func launchAtLoginStateIsReadFromService() async throws {
        try await withHarness(launchAtLoginEnabled: true) { h in
            #expect(h.manager.isLaunchAtLoginEnabled)
        }
        try await withHarness(launchAtLoginEnabled: false) { h in
            #expect(!h.manager.isLaunchAtLoginEnabled)
        }
    }

    @Test func liveEnvironmentPointsAtUserLibraryLocations() {
        let env = DriveManagerEnvironment.live()
        #expect(env.appSupportDir.hasSuffix("Library/Application Support/Horizon"))
        #expect(env.cacheDir.hasSuffix("Library/Caches/Horizon/rclone"))
        #expect(env.logFile.hasSuffix("Library/Logs/Horizon/rclone.log"))
        #expect(env.defaultMountPath.hasSuffix("/GDrive"))
        #expect(env.legacyConfigPath.hasSuffix(".config/rclone/rclone.conf"))
        #expect(env.shutdownGracePeriod == 1_000_000_000)
        #expect(env.mountTimeout == 15)
        #expect(env.mountPollInterval == 500_000_000)
        #expect(!env.mountChecker("/definitely/not/mounted/\(UUID().uuidString)"))
        _ = env.rcloneLocator()
    }

    @Test func systemLaunchAtLoginServiceReportsStatusWithoutChangingIt() {
        // Read-only: never call register()/unregister() on the real login item.
        _ = SystemLaunchAtLoginService().isEnabled
    }

    // MARK: Config migration

    @Test func legacyRcloneConfigIsCopiedWhenNoConfigExists() async throws {
        try await withHarness(legacyConfig: "[legacy]\ntype = drive\n") { h in
            let copied = try String(contentsOfFile: h.configPath, encoding: .utf8)
            #expect(copied.contains("[legacy]"))
        }
    }

    @Test func noLegacyConfigMeansNoConfigFile() async throws {
        try await withHarness { h in
            #expect(!FileManager.default.fileExists(atPath: h.configPath))
        }
    }

    // MARK: Account loading

    @Test func loadsPersistedAccountsAndDerivesMountState() async throws {
        let older = RemoteAccount(id: "a", name: "alpha", displayName: "Alpha", provider: "drive",
                                  mountPath: "/tmp/horizon-test-alpha", createdAt: Date(timeIntervalSince1970: 100))
        let newer = RemoteAccount(id: "b", name: "beta", displayName: "Beta", provider: "dropbox",
                                  mountPath: "/tmp/horizon-test-beta", createdAt: Date(timeIntervalSince1970: 200))
        try await withHarness(preloadedAccounts: [newer, older], mountedPaths: ["/tmp/horizon-test-beta"]) { h in
            let m = h.manager
            #expect(m.accounts.map(\.id) == ["a", "b"])
            #expect(m.activeAccount?.id == "a")
            #expect(m.hasConfiguredAccounts)

            #expect(m.accountStates["a"] == .disconnected)
            #expect(m.accountStates["b"] == .connected)
            #expect(m.accounts.first { $0.id == "b" }?.isConnected == true)
            #expect(m.connectedCount == 1)
            #expect(m.state == .connected)
        }
    }

    @Test func importsRemotesFoundInRcloneConfig() async throws {
        let dump = """
        {"gdrive":{"type":"drive"},"work_files":{"type":"onedrive"}}
        """
        try await withHarness(rcloneBody: FakeRclone.script(dumpJSON: dump), importRemotesAtInit: true) { h in
            let m = h.manager
            #expect(m.accounts.count == 2)

            let gdrive = try #require(m.accounts.first { $0.name == "gdrive" })
            #expect(gdrive.displayName == "Google Drive")
            #expect(gdrive.provider == "drive")
            #expect(gdrive.mountPath == h.defaultMountPath)

            let work = try #require(m.accounts.first { $0.name == "work_files" })
            #expect(work.displayName == "Work Files")
            #expect(work.provider == "onedrive")
            #expect(work.mountPath.hasSuffix("/Work Files"))

            // Imported accounts are persisted.
            #expect(Set(h.database.getAllAccounts().map(\.name)) == ["gdrive", "work_files"])
            // The dump was requested with the app's own config file.
            #expect(h.rcloneInvocations.contains("config dump --config \(h.configPath)"))
        }
    }

    @Test func importedRemoteWithoutTypeDefaultsToDrive() async throws {
        try await withHarness(rcloneBody: FakeRclone.script(dumpJSON: #"{"mystery":{}}"#), importRemotesAtInit: true) { h in
            #expect(h.manager.accounts.first?.provider == "drive")
        }
    }

    @Test func remotesAlreadyInDatabaseAreNotImportedTwice() async throws {
        let existing = RemoteAccount(id: "keep", name: "gdrive", displayName: "My Custom Name",
                                     provider: "drive", mountPath: "/tmp/horizon-test-gdrive")
        try await withHarness(
            rcloneBody: FakeRclone.script(dumpJSON: #"{"gdrive":{"type":"drive"}}"#),
            preloadedAccounts: [existing],
            importRemotesAtInit: true
        ) { h in
            #expect(h.manager.accounts.count == 1)
            #expect(h.manager.accounts.first?.id == "keep")
            #expect(h.manager.accounts.first?.displayName == "My Custom Name")
        }
    }

    @Test func malformedConfigDumpImportsNothing() async throws {
        try await withHarness(rcloneBody: FakeRclone.script(dumpJSON: "this is not json"), importRemotesAtInit: true) { h in
            #expect(h.manager.accounts.isEmpty)
        }
    }

    @Test func missingRcloneImportsNothing() async throws {
        try await withHarness(rcloneBody: nil) { h in
            #expect(h.manager.accounts.isEmpty)
            #expect(h.manager.state == .disconnected)
        }
    }

    @Test func refreshAccountsPicksUpDatabaseChanges() async throws {
        try await withHarness { h in
            let m = h.manager
            #expect(m.accounts.isEmpty)

            h.database.saveAccount(h.makeAccount(name: "added", id: "added-id"))
            m.refreshAccounts()
            #expect(m.accounts.map(\.id) == ["added-id"])
            #expect(m.activeAccount?.id == "added-id")

            // Active account is kept when still present.
            h.database.saveAccount(h.makeAccount(name: "second", id: "second-id",
                                                 createdAt: Date().addingTimeInterval(10)))
            m.refreshAccounts()
            #expect(m.accounts.count == 2)
            #expect(m.activeAccount?.id == "added-id")

            // …and replaced when it disappears.
            h.database.deleteAccount(id: "added-id")
            m.refreshAccounts()
            #expect(m.activeAccount?.id == "second-id")

            h.database.deleteAccount(id: "second-id")
            m.refreshAccounts()
            #expect(m.activeAccount == nil)
            #expect(m.accounts.isEmpty)
        }
    }

    @Test func refreshReflectsMountsThatAppearedOutsideTheApp() async throws {
        let account = RemoteAccount(id: "x", name: "x", displayName: "X", provider: "drive",
                                    mountPath: "/tmp/horizon-test-x")
        try await withHarness(preloadedAccounts: [account]) { h in
            #expect(h.manager.stateForAccount(account) == .disconnected)
            h.mounts.mount("/tmp/horizon-test-x")
            h.manager.refreshAccounts()
            #expect(h.manager.stateForAccount(account) == .connected)
        }
    }

    // MARK: Derived state

    @Test func stateForAccountFallsBackToStoredFlag() async throws {
        try await withHarness { h in
            let connected = h.makeAccount(name: "c", connected: true)
            let disconnected = h.makeAccount(name: "d", connected: false)
            #expect(h.manager.stateForAccount(connected) == .connected)
            #expect(h.manager.stateForAccount(disconnected) == .disconnected)

            h.manager.accountStates[connected.id] = .error("x")
            #expect(h.manager.stateForAccount(connected) == .error("x"))
        }
    }

    @Test func isAccountSyncingDefaultsToFalse() async throws {
        try await withHarness { h in
            let account = h.makeAccount()
            #expect(!h.manager.isAccountSyncing(account))
            h.manager.accountSyncing[account.id] = true
            #expect(h.manager.isAccountSyncing(account))
        }
    }

    @Test func connectedCountOnlyCountsConnectedAccounts() async throws {
        try await withHarness { h in
            let a = h.makeAccount(name: "a"), b = h.makeAccount(name: "b"), c = h.makeAccount(name: "c")
            h.manager.accounts = [a, b, c]
            h.manager.accountStates = [a.id: .connected, b.id: .connecting, c.id: .connected]
            #expect(h.manager.connectedCount == 2)
        }
    }

    @Test("updateOverallState priority", arguments: [
        ([DriveState.connecting, .connected, .error("e")], DriveState.connecting),
        ([DriveState.connected, .error("e"), .disconnected], DriveState.connected),
        ([DriveState.error("e"), .disconnected], DriveState.error("One or more drives encountered an issue")),
        ([DriveState.disconnected, .disconnecting], DriveState.disconnected),
        ([], DriveState.disconnected),
    ])
    func overallStatePriority(states: [DriveState], expected: DriveState) async throws {
        try await withHarness { h in
            var dict: [String: DriveState] = [:]
            for (i, s) in states.enumerated() { dict["acc-\(i)"] = s }
            h.manager.accountStates = dict
            h.manager.updateOverallState()
            #expect(h.manager.state == expected)
        }
    }

    // MARK: Last-sync text

    @Test func aggregateLastSyncText() async throws {
        try await withHarness { h in
            let m = h.manager
            #expect(m.formattedLastSync == "Ready to sync")
            m.lastSyncTime = Date()
            #expect(m.formattedLastSync == "Synced just now")
            m.lastSyncTime = Date().addingTimeInterval(-30)
            #expect(m.formattedLastSync == "Synced 30s ago")
            m.lastSyncTime = Date().addingTimeInterval(-125)
            #expect(m.formattedLastSync == "Synced 2m ago")
        }
    }

    @Test func perAccountLastSyncText() async throws {
        try await withHarness { h in
            let m = h.manager
            let account = h.makeAccount()
            #expect(m.formattedLastSync(for: account) == "Ready to sync")
            m.accountLastSync[account.id] = Date()
            #expect(m.formattedLastSync(for: account) == "Synced just now")
            m.accountLastSync[account.id] = Date().addingTimeInterval(-45)
            #expect(m.formattedLastSync(for: account) == "Synced 45s ago")
            m.accountLastSync[account.id] = Date().addingTimeInterval(-600)
            #expect(m.formattedLastSync(for: account) == "Synced 10m ago")
        }
    }

    // MARK: Onboarding flag

    @Test func onboardingFlagPersistsInInjectedDefaults() async throws {
        try await withHarness { h in
            #expect(!h.manager.hasCompletedOnboarding)
            h.manager.hasCompletedOnboarding = true
            #expect(h.manager.hasCompletedOnboarding)
            #expect(h.defaults.bool(forKey: DriveManager.onboardingKey))
            h.manager.hasCompletedOnboarding = false
            #expect(!h.defaults.bool(forKey: DriveManager.onboardingKey))
        }
    }

    // MARK: Launch at login

    @Test func toggleLaunchAtLoginRegistersThenUnregisters() async throws {
        try await withHarness { h in
            #expect(!h.manager.isLaunchAtLoginEnabled)
            h.manager.toggleLaunchAtLogin()
            #expect(h.manager.isLaunchAtLoginEnabled)
            #expect(h.launchAtLogin.registerCalls.value == 1)

            h.manager.toggleLaunchAtLogin()
            #expect(!h.manager.isLaunchAtLoginEnabled)
            #expect(h.launchAtLogin.unregisterCalls.value == 1)
        }
    }

    @Test func toggleLaunchAtLoginFailureLeavesFlagUnchanged() async throws {
        try await withHarness { h in
            h.launchAtLogin.shouldFail.value = true
            h.manager.toggleLaunchAtLogin()
            #expect(!h.manager.isLaunchAtLoginEnabled)
            #expect(h.launchAtLogin.registerCalls.value == 0)
        }
        try await withHarness(launchAtLoginEnabled: true) { h in
            h.launchAtLogin.shouldFail.value = true
            h.manager.toggleLaunchAtLogin()
            #expect(h.manager.isLaunchAtLoginEnabled)
        }
    }

    // MARK: Finder / log shortcuts

    @Test func openAccountInFinderOpensItsMountPath() async throws {
        try await withHarness { h in
            let account = h.makeAccount(name: "finder")
            h.manager.openAccountInFinder(account)
            #expect(h.openedURLs.value == [URL(fileURLWithPath: account.mountPath)])
        }
    }

    @Test func openInFinderUsesActiveAccountOtherwiseDefaultMount() async throws {
        try await withHarness { h in
            h.manager.openInFinder()
            #expect(h.openedURLs.value == [URL(fileURLWithPath: h.defaultMountPath)])

            let account = h.makeAccount(name: "active")
            h.manager.activeAccount = account
            h.manager.openInFinder()
            #expect(h.openedURLs.value.last == URL(fileURLWithPath: account.mountPath))
            #expect(h.manager.activeMountPath == account.mountPath)
        }
    }

    @Test func openLogsOpensFileWhenPresentElseItsFolder() async throws {
        try await withHarness { h in
            let logURL = URL(fileURLWithPath: h.logFile)
            h.manager.openLogs()
            #expect(h.openedURLs.value.last == logURL.deletingLastPathComponent())

            try "log".write(toFile: h.logFile, atomically: true, encoding: .utf8)
            h.manager.openLogs()
            #expect(h.openedURLs.value.last == logURL)
        }
    }

    // MARK: Cache

    @Test func clearCacheEmptiesButRecreatesCacheDirectory() async throws {
        try await withHarness { h in
            let junk = (h.cacheDir as NSString).appendingPathComponent("acct/blob")
            try FileManager.default.createDirectory(atPath: (junk as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
            try "x".write(toFile: junk, atomically: true, encoding: .utf8)

            h.manager.clearCache()

            var isDir: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: h.cacheDir, isDirectory: &isDir) && isDir.boolValue)
            #expect(!FileManager.default.fileExists(atPath: junk))
        }
    }

    // MARK: Periodic sync

    @Test func periodicSyncHooksAreSafeNoOps() async throws {
        try await withHarness { h in
            h.manager.startPeriodicSync()
            h.manager.stopPeriodicSync()
            h.manager.stopPeriodicSync()
            #expect(!h.manager.isSyncing)
        }
    }
}
