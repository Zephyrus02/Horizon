//
//  TestSupport.swift
//  HorizonTests
//
//  Shared fixtures for the unit tests. Nothing in here touches the user's real
//  ~/Library data, real mounts, real rclone remotes, Finder or login items:
//  every external dependency of `DriveManager` is replaced via `DriveManagerEnvironment`.
//

import Foundation
import AppKit
@testable import Horizon

// MARK: - Thread-safe box

final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) { _value = value }

    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.lock(); defer { lock.unlock() }
        body(&_value)
    }
}

// MARK: - Fakes

/// Pretends to be the set of currently mounted volumes.
final class MountRegistry: @unchecked Sendable {
    private let mounted = Locked<Set<String>>([])
    let unmountCalls = Locked<[String]>([])

    func mount(_ path: String) { mounted.mutate { $0.insert(path) } }
    func isMounted(_ path: String) -> Bool { mounted.value.contains(path) }
    func unmount(_ path: String) {
        unmountCalls.mutate { $0.append(path) }
        mounted.mutate { $0.remove(path) }
    }
}

final class FakeLaunchAtLogin: LaunchAtLoginService, @unchecked Sendable {
    struct Failure: Error {}

    private let state = Locked<Bool>(false)
    let registerCalls = Locked<Int>(0)
    let unregisterCalls = Locked<Int>(0)
    let shouldFail = Locked<Bool>(false)

    init(enabled: Bool = false) { state.value = enabled }

    var isEnabled: Bool { state.value }

    func register() throws {
        if shouldFail.value { throw Failure() }
        registerCalls.mutate { $0 += 1 }
        state.value = true
    }

    func unregister() throws {
        if shouldFail.value { throw Failure() }
        unregisterCalls.mutate { $0 += 1 }
        state.value = false
    }
}

// MARK: - Fake rclone executable

/// Writes a shell script that behaves like `rclone` so the real `Process` code paths
/// in `DriveManager` can be exercised deterministically.
enum FakeRclone {
    /// Default behaviour: `config dump` prints `dumpJSON`, other `config` subcommands
    /// succeed, `nfsmount` stays alive until terminated.
    static func script(dumpJSON: String = "{}", configCreate: String = "exit 0") -> String {
        """
        case "$1" in
          config)
            case "$2" in
              dump) cat <<'JSON'
        \(dumpJSON)
        JSON
              ;;
              create) \(configCreate) ;;
              *) exit 0 ;;
            esac
            ;;
          nfsmount) exec sleep 60 ;;
        esac
        """
    }

    /// Installs an executable script and returns its path. Every invocation appends
    /// its arguments (one line per call) to `logPath`.
    @discardableResult
    static func install(at path: String, logPath: String, body: String) throws -> String {
        let full = "#!/bin/sh\necho \"$@\" >> \"\(logPath)\"\n\(body)\n"
        try full.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    /// Lines the fake rclone has been invoked with so far.
    static func invocations(logPath: String) -> [String] {
        guard let text = try? String(contentsOfFile: logPath, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }
}

// MARK: - Harness

/// An isolated `DriveManager` with its own database, defaults suite, directories and fakes.
@MainActor
final class TestHarness {
    let root: URL
    let database: AccountDatabase
    let defaults: UserDefaults
    let defaultsSuite: String
    let mounts = MountRegistry()
    let launchAtLogin: FakeLaunchAtLogin
    let openedURLs = Locked<[URL]>([])
    let rclonePath = Locked<String?>(nil)
    let rcloneLog: String
    private var installedScriptPath: String?
    let manager: DriveManager

    var appSupportDir: String { root.appendingPathComponent("AppSupport").path }
    var cacheDir: String { root.appendingPathComponent("Caches").path }
    var logFile: String { root.appendingPathComponent("Logs/rclone.log").path }
    var defaultMountPath: String { root.appendingPathComponent("GDrive").path }
    var legacyConfigPath: String { root.appendingPathComponent("legacy-rclone.conf").path }
    var configPath: String { (appSupportDir as NSString).appendingPathComponent("rclone.conf") }

    init(
        rcloneBody: String? = FakeRclone.script(),
        launchAtLoginEnabled: Bool = false,
        legacyConfig: String? = nil,
        preloadedAccounts: [RemoteAccount] = [],
        mountTimeout: TimeInterval = 30,
        mountedPaths: [String] = [],
        importRemotesAtInit: Bool = false
    ) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("horizon-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        rcloneLog = root.appendingPathComponent("rclone-invocations.log").path
        if let body = rcloneBody {
            let scriptPath = root.appendingPathComponent("fake-rclone").path
            try FakeRclone.install(at: scriptPath, logPath: rcloneLog, body: body)
            // Spawning the script during DriveManager.init (to import remotes from `rclone config dump`)
            // is slow, so only do it when a test is about that import.
            if importRemotesAtInit { rclonePath.value = scriptPath }
            installedScriptPath = scriptPath
        }

        database = AccountDatabase(dbPath: root.appendingPathComponent("test.db").path)
        for account in preloadedAccounts { database.saveAccount(account) }

        defaultsSuite = "horizon.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuite)!
        launchAtLogin = FakeLaunchAtLogin(enabled: launchAtLoginEnabled)

        if let legacyConfig {
            try legacyConfig.write(toFile: root.appendingPathComponent("legacy-rclone.conf").path,
                                   atomically: true, encoding: .utf8)
        }
        for path in mountedPaths { mounts.mount(path) }

        let mounts = self.mounts
        let rclonePath = self.rclonePath
        let openedURLs = self.openedURLs
        let env = DriveManagerEnvironment(
            appSupportDir: root.appendingPathComponent("AppSupport").path,
            cacheDir: root.appendingPathComponent("Caches").path,
            logFile: root.appendingPathComponent("Logs/rclone.log").path,
            defaultMountPath: root.appendingPathComponent("GDrive").path,
            legacyConfigPath: root.appendingPathComponent("legacy-rclone.conf").path,
            database: database,
            userDefaults: defaults,
            launchAtLogin: launchAtLogin,
            rcloneLocator: { rclonePath.value },
            mountChecker: { mounts.isMounted($0) },
            unmounter: { mounts.unmount($0) },
            urlOpener: { url in openedURLs.mutate { $0.append(url) } },
            shutdownGracePeriod: 0,
            mountTimeout: mountTimeout,
            mountPollInterval: 20_000_000
        )
        manager = DriveManager(environment: env)
        if let installedScriptPath { rclonePath.value = installedScriptPath }
    }

    /// A path inside the temp root, suitable as an account mount point.
    func mountPoint(_ name: String) -> String {
        root.appendingPathComponent("mnt-\(name)").path
    }

    func makeAccount(
        name: String = "work_drive",
        displayName: String? = nil,
        provider: String = "drive",
        id: String = UUID().uuidString,
        connected: Bool = false,
        createdAt: Date = Date()
    ) -> RemoteAccount {
        RemoteAccount(
            id: id,
            name: name,
            displayName: displayName ?? name,
            provider: provider,
            mountPath: mountPoint(name),
            isConnected: connected,
            autoConnect: true,
            createdAt: createdAt
        )
    }

    var rcloneInvocations: [String] { FakeRclone.invocations(logPath: rcloneLog) }

    /// The fake rclone logs asynchronously after being spawned, so poll for the call.
    func waitForInvocation(prefix: String, timeout: TimeInterval = 20) async -> String? {
        _ = await waitUntil(timeout: timeout) { rcloneInvocations.contains { $0.hasPrefix(prefix) } }
        return rcloneInvocations.first { $0.hasPrefix(prefix) }
    }

    /// Stops every spawned process and removes all temp state. Call from `defer`.
    func cleanup() {
        manager.disconnectSync()
        database.close()   // don't unlink the file under an open SQLite handle
        defaults.removePersistentDomain(forName: defaultsSuite)
        try? FileManager.default.removeItem(at: root)
    }
}

/// Runs `body` with a fresh harness and always cleans up afterwards.
@MainActor
func withHarness(
    rcloneBody: String? = FakeRclone.script(),
    launchAtLoginEnabled: Bool = false,
    legacyConfig: String? = nil,
    preloadedAccounts: [RemoteAccount] = [],
    mountTimeout: TimeInterval = 30,
    mountedPaths: [String] = [],
    importRemotesAtInit: Bool = false,
    _ body: (TestHarness) async throws -> Void
) async throws {
    let harness = try TestHarness(
        rcloneBody: rcloneBody,
        launchAtLoginEnabled: launchAtLoginEnabled,
        legacyConfig: legacyConfig,
        preloadedAccounts: preloadedAccounts,
        mountTimeout: mountTimeout,
        mountedPaths: mountedPaths,
        importRemotesAtInit: importRemotesAtInit
    )
    do {
        try await body(harness)
        harness.cleanup()
    } catch {
        harness.cleanup()
        throw error
    }
}

// MARK: - Async helpers

/// Polls `condition` on the main actor until it holds or `timeout` elapses.
@MainActor
@discardableResult
func waitUntil(timeout: TimeInterval = 20, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
}

/// A unique throwaway directory (removed by the caller).
func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("horizon-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
