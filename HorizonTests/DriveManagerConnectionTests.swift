//
//  DriveManagerConnectionTests.swift
//  HorizonTests
//
//  The sign-in flow (`rclone config create`), mounting, disconnecting, deleting and
//  syncing, driven against a fake rclone shell script instead of the real binary.
//

import Testing
import Foundation
@testable import Horizon

@MainActor
@Suite("DriveManager – authentication flow", .serialized)
struct DriveManagerAuthTests {

    @Test func startConnectionFailsWhenRcloneIsMissing() async throws {
        try await withHarness(rcloneBody: nil) { h in
            let ok = await h.manager.startConnection(displayName: "X", mountPath: h.mountPoint("x"))
            #expect(!ok)
            #expect(h.manager.authError == "rclone executable was not found.")
            #expect(!h.manager.isAuthenticating)
            #expect(h.manager.accounts.isEmpty)
        }
    }

    @Test func successfulSignInCreatesPersistsAndMountsAccount() async throws {
        try await withHarness { h in
            let mountPath = h.mountPoint("google")
            let ok = await h.manager.startConnection(displayName: "My Google Drive", mountPath: mountPath)
            #expect(ok)

            let m = h.manager
            #expect(!m.isAuthenticating)
            #expect(m.authError == nil)
            #expect(m.hasCompletedOnboarding)
            #expect(m.accounts.count == 1)

            let account = try #require(m.accounts.first)
            #expect(account.name == "my_google_drive")
            #expect(account.displayName == "My Google Drive")
            #expect(account.provider == "drive")
            #expect(account.mountPath == mountPath)
            #expect(m.activeAccount?.id == account.id)
            #expect(FileManager.default.fileExists(atPath: mountPath))   // mount point created

            // Persisted to SQLite.
            #expect(h.database.getAllAccounts().map(\.name) == ["my_google_drive"])

            // rclone was asked to create the remote with the shared client id (no custom creds).
            let create = try #require(h.rcloneInvocations.first { $0.hasPrefix("config create") })
            #expect(create == "config create my_google_drive drive scope drive --config \(h.configPath) config_shared_client_id true")

            // The new drive is mounted straight away.
            #expect(m.accountStates[account.id] == .connecting)
            #expect(await h.waitForInvocation(prefix: "nfsmount my_google_drive:") != nil)
        }
    }

    @Test func customClientCredentialsArePassedToRclone() async throws {
        try await withHarness { h in
            _ = await h.manager.startConnection(
                displayName: "Mine", mountPath: h.mountPoint("mine"),
                clientId: "  my-id.apps.googleusercontent.com \n", clientSecret: " s3cret "
            )
            let create = try #require(h.rcloneInvocations.first { $0.hasPrefix("config create") })
            #expect(create.hasSuffix("client_id my-id.apps.googleusercontent.com client_secret s3cret"))
            #expect(!create.contains("config_shared_client_id"))
        }
    }

    @Test("incomplete or blank credentials fall back to the shared client id", arguments: [
        ("id-only", ""),
        ("", "secret-only"),
        ("   ", "   "),
    ])
    func incompleteCredentialsUseSharedClient(clientId: String, clientSecret: String) async throws {
        try await withHarness { h in
            _ = await h.manager.startConnection(
                displayName: "Mine", mountPath: h.mountPoint("mine"),
                clientId: clientId, clientSecret: clientSecret
            )
            let create = try #require(h.rcloneInvocations.first { $0.hasPrefix("config create") })
            #expect(create.hasSuffix("config_shared_client_id true"))
        }
    }

    @Test func providerIsForwardedToRclone() async throws {
        try await withHarness { h in
            _ = await h.manager.startConnection(displayName: "Box", mountPath: h.mountPoint("box"), provider: "dropbox")
            let create = try #require(h.rcloneInvocations.first { $0.hasPrefix("config create") })
            #expect(create.hasPrefix("config create box dropbox "))
            #expect(h.manager.accounts.first?.provider == "dropbox")
        }
    }

    @Test func duplicateNamesGetNumericSuffix() async throws {
        try await withHarness { h in
            _ = await h.manager.startConnection(displayName: "Drive", mountPath: h.mountPoint("1"))
            _ = await h.manager.startConnection(displayName: "Drive", mountPath: h.mountPoint("2"))
            _ = await h.manager.startConnection(displayName: "Drive", mountPath: h.mountPoint("3"))
            #expect(h.manager.accounts.map(\.name) == ["drive", "drive_2", "drive_3"])
            #expect(h.manager.accounts.map(\.displayName) == ["Drive", "Drive", "Drive"])
        }
    }

    @Test func mountPathTildeIsExpanded() async throws {
        try await withHarness { h in
            let name = "horizon-test-\(UUID().uuidString)"
            let ok = await h.manager.startConnection(displayName: "Tilde", mountPath: "~/\(name)")
            #expect(ok)
            let expanded = ("~/\(name)" as NSString).expandingTildeInPath
            defer { try? FileManager.default.removeItem(atPath: expanded) }
            #expect(h.manager.accounts.first?.mountPath == expanded)
            #expect(!(h.manager.accounts.first?.mountPath.hasPrefix("~") ?? true))
        }
    }

    @Test func failedSignInReportsRcloneStderr() async throws {
        let body = FakeRclone.script(configCreate: #"echo "invalid_grant: token expired" >&2; exit 1"#)
        try await withHarness(rcloneBody: body) { h in
            let ok = await h.manager.startConnection(displayName: "Bad", mountPath: h.mountPoint("bad"))
            #expect(!ok)
            #expect(h.manager.authError == "invalid_grant: token expired")
            #expect(!h.manager.isAuthenticating)
            #expect(h.manager.accounts.isEmpty)
            #expect(h.database.getAllAccounts().isEmpty)
            #expect(!h.manager.hasCompletedOnboarding)
        }
    }

    @Test func failedSignInWithoutStderrUsesGenericMessage() async throws {
        let body = FakeRclone.script(configCreate: "exit 1")
        try await withHarness(rcloneBody: body) { h in
            let ok = await h.manager.startConnection(displayName: "Bad", mountPath: h.mountPoint("bad"))
            #expect(!ok)
            #expect(h.manager.authError == "Authentication failed or was cancelled.")
        }
    }

    @Test func signInFailsCleanlyWhenRcloneCannotLaunch() async throws {
        try await withHarness { h in
            // A file that exists but is not executable → Process.run() throws.
            let notExecutable = h.root.appendingPathComponent("not-executable").path
            try "echo hi".write(toFile: notExecutable, atomically: true, encoding: .utf8)
            h.rclonePath.value = notExecutable

            let ok = await h.manager.startConnection(displayName: "X", mountPath: h.mountPoint("x"))
            #expect(!ok)
            #expect(h.manager.authError == "Authentication failed or was cancelled.")
            #expect(!h.manager.isAuthenticating)
        }
    }

    @Test func startGoogleDriveConnectionUsesDefaultMountAndDriveProvider() async throws {
        try await withHarness { h in
            let ok = await h.manager.startGoogleDriveConnection()
            #expect(ok)
            let account = try #require(h.manager.accounts.first)
            #expect(account.displayName == "Google Drive")
            #expect(account.provider == "drive")
            #expect(account.mountPath == h.defaultMountPath)
        }
    }

    @Test func isAuthenticatingWhileRcloneIsRunning() async throws {
        let body = FakeRclone.script(configCreate: "sleep 0.4; exit 0")
        try await withHarness(rcloneBody: body) { h in
            let task = Task { await h.manager.startConnection(displayName: "Slow", mountPath: h.mountPoint("slow")) }
            let started = await waitUntil { h.manager.isAuthenticating }
            #expect(started)
            #expect(h.manager.authStatusText == "Opening browser for Drive authorization...")
            let ok = await task.value
            #expect(ok)
            #expect(!h.manager.isAuthenticating)
        }
    }

    @Test func cancellingSignInTerminatesRclone() async throws {
        let body = FakeRclone.script(configCreate: "exec sleep 30")
        try await withHarness(rcloneBody: body) { h in
            let task = Task { await h.manager.startConnection(displayName: "Hang", mountPath: h.mountPoint("hang")) }
            #expect(await waitUntil { h.manager.isAuthenticating })
            // Give the detached task a moment to actually launch the process.
            try await Task.sleep(nanoseconds: 200_000_000)

            h.manager.cancelAuthentication()
            #expect(!h.manager.isAuthenticating)
            #expect(h.manager.authStatusText.isEmpty)

            let ok = await task.value
            #expect(!ok)
            #expect(h.manager.accounts.isEmpty)
        }
    }

    @Test func cancelAuthenticationWithNothingRunningResetsAuthState() async throws {
        try await withHarness { h in
            h.manager.isAuthenticating = true
            h.manager.authStatusText = "Opening browser…"
            h.manager.authError = "old error"
            h.manager.cancelAuthentication()
            #expect(!h.manager.isAuthenticating)
            #expect(h.manager.authStatusText.isEmpty)
            #expect(h.manager.authError == nil)
        }
    }
}

@MainActor
@Suite("DriveManager – mounting & lifecycle", .serialized)
struct DriveManagerLifecycleTests {

    // MARK: connectAccount

    @Test func connectWithoutRcloneSetsErrorState() async throws {
        try await withHarness(rcloneBody: nil) { h in
            let account = h.makeAccount()
            h.manager.connectAccount(account)
            #expect(h.manager.accountStates[account.id] == .error("rclone executable not found"))
            #expect(h.manager.state.isError)
        }
    }

    @Test func connectOnAlreadyMountedPathMarksConnectedWithoutSpawning() async throws {
        let account = RemoteAccount(id: "m", name: "mounted", provider: "drive", mountPath: "/tmp/horizon-test-mounted")
        try await withHarness(preloadedAccounts: [account], mountedPaths: ["/tmp/horizon-test-mounted"]) { h in
            h.manager.accountStates["m"] = .disconnected
            h.manager.connectAccount(account)
            #expect(h.manager.accountStates["m"] == .connected)
            #expect(h.database.getAllAccounts().first?.isConnected == true)
            #expect(!h.rcloneInvocations.contains { $0.hasPrefix("nfsmount") })
        }
    }

    @Test func connectLaunchesNfsMountAndBecomesConnectedOnceMounted() async throws {
        try await withHarness { h in
            let account = h.makeAccount(name: "work", displayName: "Work")
            h.database.saveAccount(account)
            h.manager.refreshAccounts()

            h.manager.connectAccount(account)
            #expect(h.manager.accountStates[account.id] == .connecting)
            #expect(h.manager.state == .connecting)

            let nfs = try #require(await h.waitForInvocation(prefix: "nfsmount"))
            #expect(nfs.hasPrefix("nfsmount work: \(account.mountPath) --config \(h.configPath)"))
            #expect(nfs.contains("--volname Work"))
            #expect(nfs.contains("--vfs-cache-mode full"))
            #expect(nfs.contains("--rc-addr 127.0.0.1:5572"))
            #expect(nfs.contains("--log-file \((h.logFile as NSString).deletingLastPathComponent)/rclone-work.log"))

            // Mount point and per-account cache directories were prepared.
            #expect(FileManager.default.fileExists(atPath: account.mountPath))
            #expect(FileManager.default.fileExists(atPath: "\(h.cacheDir)/work/nfs-handles"))

            // The "volume" appears → readiness poll flips the state.
            h.mounts.mount(account.mountPath)
            #expect(await waitUntil { h.manager.accountStates[account.id] == .connected })
            #expect(h.manager.state == .connected)
            #expect(h.manager.accounts.first?.isConnected == true)
            #expect(h.database.getAllAccounts().first?.isConnected == true)
        }
    }

    @Test func eachAccountGetsItsOwnRcPort() async throws {
        try await withHarness { h in
            let a = h.makeAccount(name: "one"), b = h.makeAccount(name: "two")
            h.manager.connectAccount(a)
            h.manager.connectAccount(b)
            _ = await waitUntil { h.rcloneInvocations.filter { $0.hasPrefix("nfsmount") }.count >= 2 }
            let calls = h.rcloneInvocations.filter { $0.hasPrefix("nfsmount") }
            #expect(calls.count == 2)
            #expect(calls.first { $0.hasPrefix("nfsmount one:") }?.contains("127.0.0.1:5572") == true)
            #expect(calls.first { $0.hasPrefix("nfsmount two:") }?.contains("127.0.0.1:5573") == true)
        }
    }

    @Test func launchFailureSetsErrorState() async throws {
        try await withHarness { h in
            let notExecutable = h.root.appendingPathComponent("not-executable").path
            try "echo hi".write(toFile: notExecutable, atomically: true, encoding: .utf8)
            h.rclonePath.value = notExecutable

            let account = h.makeAccount()
            h.manager.connectAccount(account)
            guard case .error(let message) = h.manager.accountStates[account.id] else {
                Issue.record("expected an error state, got \(String(describing: h.manager.accountStates[account.id]))")
                return
            }
            #expect(message.hasPrefix("Failed to launch process:"))
        }
    }

    @Test func mountTimeoutTearsTheAccountDown() async throws {
        try await withHarness(mountTimeout: 0.3) { h in
            let account = h.makeAccount(name: "slowmount")
            h.database.saveAccount(account)
            h.manager.connectAccount(account)

            // Never mark the path as mounted → timeout → disconnectAccount cleans up.
            #expect(await waitUntil { h.manager.accountStates[account.id] == .disconnected })
            #expect(h.mounts.unmountCalls.value.contains(account.mountPath))
            #expect(h.database.getAllAccounts().first?.isConnected == false)
        }
    }

    @Test func rcloneExitingEarlyIsNotLeftConnecting() async throws {
        let body = """
        case "$1" in
          nfsmount) exit 3 ;;
          *) exit 0 ;;
        esac
        """
        try await withHarness(rcloneBody: body) { h in
            let account = h.makeAccount(name: "crash")
            h.database.saveAccount(account)
            h.manager.connectAccount(account)

            #expect(await waitUntil { h.manager.accountStates[account.id] != .connecting })
            #expect(await waitUntil { h.manager.accountStates[account.id] == .disconnected })
            #expect(h.manager.accounts.first { $0.id == account.id }?.isConnected != true)
        }
    }

    // MARK: disconnectAccount

    private func connect(_ h: TestHarness, name: String = "acct") async -> RemoteAccount {
        let account = h.makeAccount(name: name)
        h.database.saveAccount(account)
        h.manager.refreshAccounts()
        h.manager.connectAccount(account)
        h.mounts.mount(account.mountPath)
        _ = await waitUntil { h.manager.accountStates[account.id] == .connected }
        return account
    }

    @Test func disconnectUnmountsTerminatesAndUpdatesState() async throws {
        try await withHarness { h in
            let account = await connect(h)
            #expect(h.manager.accountStates[account.id] == .connected)

            h.manager.disconnectAccount(account)
            #expect(h.manager.accountStates[account.id] == .disconnecting)

            #expect(await waitUntil { h.manager.accountStates[account.id] == .disconnected })
            #expect(h.mounts.unmountCalls.value.contains(account.mountPath))
            #expect(!h.mounts.isMounted(account.mountPath))
            #expect(h.manager.accounts.first?.isConnected == false)
            #expect(h.database.getAllAccounts().first?.isConnected == false)
            #expect(h.manager.state == .disconnected)
        }
    }

    @Test func disconnectingAnAccountThatNeverConnectedStillSettles() async throws {
        try await withHarness { h in
            let account = h.makeAccount(name: "idle")
            h.manager.disconnectAccount(account)
            #expect(await waitUntil { h.manager.accountStates[account.id] == .disconnected })
        }
    }

    @Test func toggleAccountConnectionFlipsBetweenConnectAndDisconnect() async throws {
        try await withHarness { h in
            let account = h.makeAccount(name: "toggle")
            h.database.saveAccount(account)
            h.manager.refreshAccounts()

            h.manager.toggleAccountConnection(account)       // disconnected → connect
            #expect(h.manager.accountStates[account.id] == .connecting)

            h.manager.toggleAccountConnection(account)       // connecting → disconnect
            #expect(h.manager.accountStates[account.id] == .disconnecting)
            #expect(await waitUntil { h.manager.accountStates[account.id] == .disconnected })

            h.manager.accountStates[account.id] = .connected
            h.manager.toggleAccountConnection(account)       // connected → disconnect
            #expect(h.manager.accountStates[account.id] == .disconnecting)
            #expect(await waitUntil { h.manager.accountStates[account.id] == .disconnected })
        }
    }

    // MARK: Global connect / disconnect

    @Test func connectUsesActiveAccountThenFirstAccount() async throws {
        try await withHarness { h in
            let first = h.makeAccount(name: "first", createdAt: Date(timeIntervalSince1970: 1))
            let second = h.makeAccount(name: "second", createdAt: Date(timeIntervalSince1970: 2))
            h.manager.accounts = [first, second]

            h.manager.activeAccount = second
            h.manager.connect()
            #expect(h.manager.accountStates[second.id] == .connecting)
            #expect(h.manager.accountStates[first.id] == nil)

            h.manager.activeAccount = nil
            h.manager.connect()
            #expect(h.manager.accountStates[first.id] == .connecting)
        }
    }

    @Test func connectWithNoAccountsDoesNothing() async throws {
        try await withHarness { h in
            h.manager.connect()
            #expect(h.manager.accountStates.isEmpty)
            #expect(h.manager.state == .disconnected)
        }
    }

    @Test func toggleConnectionConnectsWhenIdleAndDisconnectsWhenConnected() async throws {
        try await withHarness { h in
            let account = h.makeAccount(name: "global")
            h.database.saveAccount(account)
            h.manager.refreshAccounts()

            h.manager.toggleConnection()
            #expect(h.manager.accountStates[account.id] == .connecting)

            h.mounts.mount(account.mountPath)
            #expect(await waitUntil { h.manager.state.isConnected })

            h.manager.toggleConnection()
            #expect(await waitUntil { h.manager.accountStates[account.id] == .disconnected })
            #expect(h.manager.state == .disconnected)
        }
    }

    @Test func disconnectOnlyAffectsConnectedAccounts() async throws {
        try await withHarness { h in
            let up = await connect(h, name: "up")
            let down = h.makeAccount(name: "down")
            h.manager.accounts.append(down)

            h.manager.disconnect()
            #expect(h.manager.accountStates[up.id] == .disconnecting)
            #expect(h.manager.accountStates[down.id] == nil)
            #expect(await waitUntil { h.manager.accountStates[up.id] == .disconnected })
            #expect(!h.mounts.unmountCalls.value.contains(down.mountPath))
        }
    }

    @Test func disconnectSyncUnmountsEverythingAndStopsProcesses() async throws {
        try await withHarness { h in
            let a = await connect(h, name: "sa")
            let b = await connect(h, name: "sb")
            h.manager.disconnectSync()
            #expect(Set(h.mounts.unmountCalls.value).isSuperset(of: [a.mountPath, b.mountPath]))
        }
    }

    // MARK: Delete / logout

    @Test func deleteAccountRemovesItEverywhere() async throws {
        try await withHarness { h in
            let keep = h.makeAccount(name: "keep", createdAt: Date(timeIntervalSince1970: 1))
            let doomed = h.makeAccount(name: "doomed", createdAt: Date(timeIntervalSince1970: 2))
            h.database.saveAccount(keep)
            h.database.saveAccount(doomed)
            h.manager.refreshAccounts()
            h.manager.activeAccount = doomed
            h.manager.hasCompletedOnboarding = true

            await h.manager.deleteAccount(doomed)

            #expect(h.manager.accounts.map(\.id) == [keep.id])
            #expect(h.manager.activeAccount?.id == keep.id)
            #expect(h.database.getAllAccounts().map(\.id) == [keep.id])
            #expect(h.rcloneInvocations.contains("config delete doomed --config \(h.configPath)"))
            #expect(h.manager.hasCompletedOnboarding)            // another account remains
            #expect(h.mounts.unmountCalls.value.contains(doomed.mountPath))
        }
    }

    @Test func deletingTheLastAccountResetsOnboarding() async throws {
        try await withHarness { h in
            let only = h.makeAccount(name: "only")
            h.database.saveAccount(only)
            h.manager.refreshAccounts()
            h.manager.hasCompletedOnboarding = true

            await h.manager.deleteAccount(only)

            #expect(h.manager.accounts.isEmpty)
            #expect(h.manager.activeAccount == nil)
            #expect(!h.manager.hasCompletedOnboarding)
            #expect(h.manager.state == .disconnected)
        }
    }

    @Test func deleteWithoutRcloneStillRemovesLocalRecord() async throws {
        try await withHarness(rcloneBody: nil) { h in
            let account = h.makeAccount(name: "norclone")
            h.database.saveAccount(account)
            h.manager.refreshAccounts()
            await h.manager.deleteAccount(account)
            #expect(h.manager.accounts.isEmpty)
            #expect(h.database.getAllAccounts().isEmpty)
        }
    }

    @Test func deletingANonActiveAccountKeepsTheActiveOne() async throws {
        try await withHarness { h in
            let a = h.makeAccount(name: "a", createdAt: Date(timeIntervalSince1970: 1))
            let b = h.makeAccount(name: "b", createdAt: Date(timeIntervalSince1970: 2))
            h.database.saveAccount(a); h.database.saveAccount(b)
            h.manager.refreshAccounts()
            h.manager.activeAccount = a
            await h.manager.deleteAccount(b)
            #expect(h.manager.activeAccount?.id == a.id)
        }
    }

    @Test func logoutRevokesThenRemovesAccount() async throws {
        try await withHarness { h in
            let keep = h.makeAccount(name: "stay", createdAt: Date(timeIntervalSince1970: 1))
            let leaving = h.makeAccount(name: "leaving", createdAt: Date(timeIntervalSince1970: 2))
            h.database.saveAccount(keep); h.database.saveAccount(leaving)
            h.manager.refreshAccounts()
            h.manager.activeAccount = leaving

            await h.manager.logoutAccount(leaving)

            let calls = h.rcloneInvocations
            let disconnectIdx = try #require(calls.firstIndex(of: "config disconnect leaving: --config \(h.configPath)"))
            let deleteIdx = try #require(calls.firstIndex(of: "config delete leaving --config \(h.configPath)"))
            #expect(disconnectIdx < deleteIdx)

            #expect(h.manager.accounts.map(\.id) == [keep.id])
            #expect(h.manager.activeAccount?.id == keep.id)
            #expect(h.database.getAllAccounts().map(\.id) == [keep.id])
        }
    }

    @Test func logoutOfLastAccountResetsOnboarding() async throws {
        try await withHarness { h in
            let only = h.makeAccount(name: "solo")
            h.database.saveAccount(only)
            h.manager.refreshAccounts()
            h.manager.hasCompletedOnboarding = true
            await h.manager.logoutAccount(only)
            #expect(h.manager.accounts.isEmpty)
            #expect(!h.manager.hasCompletedOnboarding)
            #expect(h.manager.state == .disconnected)
        }
    }

    @Test func logoutWithoutRcloneKeepsTheAccount() async throws {
        try await withHarness(rcloneBody: nil) { h in
            let account = h.makeAccount(name: "stuck")
            h.database.saveAccount(account)
            h.manager.refreshAccounts()
            await h.manager.logoutAccount(account)
            #expect(h.manager.accounts.count == 1)
            #expect(h.database.getAllAccounts().count == 1)
        }
    }

    // MARK: Sync

    @Test func syncAccountRecordsTimestampsForConnectedAccount() async throws {
        try await withHarness { h in
            let account = await connect(h, name: "sync")
            #expect(!h.manager.isSyncing)

            h.manager.syncAccount(account)
            #expect(await waitUntil { h.manager.accountLastSync[account.id] != nil })
            #expect(await waitUntil { !h.manager.isAccountSyncing(account) && !h.manager.isSyncing })
            #expect(h.manager.lastSyncTime != nil)
            #expect(h.manager.formattedLastSync(for: account) == "Synced just now")
        }
    }

    @Test func syncAccountWithoutForceRefreshSkipsRcCall() async throws {
        try await withHarness { h in
            let account = h.makeAccount(name: "light")
            h.manager.accountStates[account.id] = .connected
            h.manager.syncAccount(account, forceRefresh: false)
            #expect(await waitUntil { h.manager.accountLastSync[account.id] != nil })
        }
    }

    @Test func syncIgnoresAccountsThatAreNotConnected() async throws {
        try await withHarness { h in
            let idle = h.makeAccount(name: "idle")
            h.manager.accountStates[idle.id] = .disconnected
            h.manager.syncAccount(idle)
            try await Task.sleep(nanoseconds: 150_000_000)
            #expect(h.manager.accountLastSync[idle.id] == nil)
            #expect(h.manager.lastSyncTime == nil)
        }
    }

    @Test func syncNowSyncsEveryConnectedAccountOnly() async throws {
        try await withHarness { h in
            let a = h.makeAccount(name: "a"), b = h.makeAccount(name: "b"), c = h.makeAccount(name: "c")
            h.manager.accounts = [a, b, c]
            h.manager.accountStates = [a.id: .connected, b.id: .connected, c.id: .disconnected]

            h.manager.syncNow()

            #expect(await waitUntil { h.manager.accountLastSync[a.id] != nil && h.manager.accountLastSync[b.id] != nil })
            #expect(h.manager.accountLastSync[c.id] == nil)
        }
    }
}
