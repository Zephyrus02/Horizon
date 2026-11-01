//
//  AccountDatabaseTests.swift
//  HorizonTests
//
//  Tests for the SQLite-backed account store. Every test uses its own temp database file.
//

import Testing
import Foundation
@testable import Horizon

@Suite("AccountDatabase")
struct AccountDatabaseTests {

    private func withDatabase(_ body: (AccountDatabase, String) throws -> Void) throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("accounts.db").path
        try body(AccountDatabase(dbPath: path), path)
    }

    private func account(
        id: String = UUID().uuidString,
        name: String = "remote",
        displayName: String = "Remote",
        provider: String = "drive",
        mountPath: String = "/tmp/remote",
        email: String? = nil,
        connected: Bool = false,
        autoConnect: Bool = true,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> RemoteAccount {
        RemoteAccount(id: id, name: name, displayName: displayName, provider: provider,
                      accountEmail: email, mountPath: mountPath,
                      isConnected: connected, autoConnect: autoConnect, createdAt: createdAt)
    }

    // MARK: Setup

    @Test func usesCustomPathAndCreatesFile() throws {
        try withDatabase { db, path in
            #expect(db.dbPath == path)
            #expect(FileManager.default.fileExists(atPath: path))
            #expect(db.getAllAccounts().isEmpty)
        }
    }

    @Test func sharedInstanceLivesInApplicationSupport() {
        let path = AccountDatabase.shared.dbPath
        #expect(path.hasSuffix("Library/Application Support/Horizon/horizon.db"))
    }

    @Test func reopeningExistingDatabaseKeepsData() throws {
        try withDatabase { db, path in
            db.saveAccount(account(id: "persisted", name: "keep"))
            let reopened = AccountDatabase(dbPath: path)
            let accounts = reopened.getAllAccounts()
            #expect(accounts.count == 1)
            #expect(accounts.first?.id == "persisted")
        }
    }

    @Test func unwritableLocationDegradesGracefully() {
        let db = AccountDatabase(dbPath: "/nonexistent-dir-\(UUID().uuidString)/accounts.db")
        // None of these may crash; there is simply nothing persisted.
        db.saveAccount(account())
        db.updateConnectionStatus(id: "x", isConnected: true)
        db.deleteAccount(id: "x")
        db.deleteAccountByRemoteName("x")
        #expect(db.getAllAccounts().isEmpty)
    }

    // MARK: Insert / read

    @Test func savedAccountRoundTripsAllColumns() throws {
        try withDatabase { db, _ in
            let created = Date(timeIntervalSince1970: 1_650_123_456.5)
            db.saveAccount(account(
                id: "id-1", name: "work_drive", displayName: "Work Drive", provider: "onedrive",
                mountPath: "/Volumes/Work Drive", email: "me@example.com",
                connected: true, autoConnect: false, createdAt: created
            ))

            let loaded = try #require(db.getAllAccounts().first)
            #expect(loaded.id == "id-1")
            #expect(loaded.name == "work_drive")
            #expect(loaded.displayName == "Work Drive")
            #expect(loaded.provider == "onedrive")
            #expect(loaded.mountPath == "/Volumes/Work Drive")
            #expect(loaded.accountEmail == "me@example.com")
            #expect(loaded.isConnected)
            #expect(!loaded.autoConnect)
            #expect(abs(loaded.createdAt.timeIntervalSince1970 - created.timeIntervalSince1970) < 0.001)
            #expect(loaded.accountName == nil)   // not persisted
        }
    }

    @Test func nilEmailIsStoredAsNull() throws {
        try withDatabase { db, _ in
            db.saveAccount(account(id: "a", name: "a", email: nil))
            #expect(db.getAllAccounts().first?.accountEmail == nil)
        }
    }

    @Test func accountsAreOrderedByCreationDate() throws {
        try withDatabase { db, _ in
            db.saveAccount(account(id: "newest", name: "c", createdAt: Date(timeIntervalSince1970: 3000)))
            db.saveAccount(account(id: "oldest", name: "a", createdAt: Date(timeIntervalSince1970: 1000)))
            db.saveAccount(account(id: "middle", name: "b", createdAt: Date(timeIntervalSince1970: 2000)))
            #expect(db.getAllAccounts().map(\.id) == ["oldest", "middle", "newest"])
        }
    }

    @Test func specialCharactersAndUnicodeSurvive() throws {
        try withDatabase { db, _ in
            let tricky = "Robert'); DROP TABLE accounts;-- ünï 日本語 🚀"
            db.saveAccount(account(id: "t", name: "t", displayName: tricky, mountPath: "/tmp/\(tricky)"))
            let loaded = try #require(db.getAllAccounts().first)
            #expect(loaded.displayName == tricky)
            #expect(loaded.mountPath == "/tmp/\(tricky)")
            // The table must still be intact.
            db.saveAccount(account(id: "t2", name: "t2"))
            #expect(db.getAllAccounts().count == 2)
        }
    }

    // MARK: Upsert

    @Test func savingSameIdUpdatesInPlace() throws {
        try withDatabase { db, _ in
            db.saveAccount(account(id: "same", name: "one", displayName: "One", provider: "drive",
                                   mountPath: "/a", connected: false, autoConnect: true))
            db.saveAccount(account(id: "same", name: "two", displayName: "Two", provider: "dropbox",
                                   mountPath: "/b", email: "x@y.z", connected: true, autoConnect: false))

            let all = db.getAllAccounts()
            #expect(all.count == 1)
            let updated = try #require(all.first)
            #expect(updated.name == "two")
            #expect(updated.displayName == "Two")
            #expect(updated.provider == "dropbox")
            #expect(updated.mountPath == "/b")
            #expect(updated.accountEmail == "x@y.z")
            #expect(updated.isConnected)
            #expect(!updated.autoConnect)
        }
    }

    @Test func upsertKeepsOriginalCreationDate() throws {
        try withDatabase { db, _ in
            db.saveAccount(account(id: "same", createdAt: Date(timeIntervalSince1970: 1000)))
            db.saveAccount(account(id: "same", createdAt: Date(timeIntervalSince1970: 9999)))
            #expect(db.getAllAccounts().first?.createdAt.timeIntervalSince1970 == 1000)
        }
    }

    @Test func remoteNameMustBeUnique() throws {
        try withDatabase { db, _ in
            db.saveAccount(account(id: "first", name: "dup"))
            db.saveAccount(account(id: "second", name: "dup"))   // rejected by UNIQUE constraint
            let all = db.getAllAccounts()
            #expect(all.count == 1)
            #expect(all.first?.id == "first")
        }
    }

    // MARK: Update connection state

    @Test func updateConnectionStatusTogglesFlag() throws {
        try withDatabase { db, _ in
            db.saveAccount(account(id: "a", name: "a", connected: false))
            db.updateConnectionStatus(id: "a", isConnected: true)
            #expect(db.getAllAccounts().first?.isConnected == true)
            db.updateConnectionStatus(id: "a", isConnected: false)
            #expect(db.getAllAccounts().first?.isConnected == false)
        }
    }

    @Test func updateConnectionStatusOnlyAffectsTargetRow() throws {
        try withDatabase { db, _ in
            db.saveAccount(account(id: "a", name: "a", createdAt: Date(timeIntervalSince1970: 1)))
            db.saveAccount(account(id: "b", name: "b", createdAt: Date(timeIntervalSince1970: 2)))
            db.updateConnectionStatus(id: "b", isConnected: true)
            let all = db.getAllAccounts()
            #expect(all.first { $0.id == "a" }?.isConnected == false)
            #expect(all.first { $0.id == "b" }?.isConnected == true)
        }
    }

    @Test func updateConnectionStatusForUnknownIdIsNoOp() throws {
        try withDatabase { db, _ in
            db.saveAccount(account(id: "a", name: "a"))
            db.updateConnectionStatus(id: "missing", isConnected: true)
            #expect(db.getAllAccounts().count == 1)
            #expect(db.getAllAccounts().first?.isConnected == false)
        }
    }

    // MARK: Delete

    @Test func deleteAccountRemovesOnlyThatRow() throws {
        try withDatabase { db, _ in
            db.saveAccount(account(id: "a", name: "a", createdAt: Date(timeIntervalSince1970: 1)))
            db.saveAccount(account(id: "b", name: "b", createdAt: Date(timeIntervalSince1970: 2)))
            db.deleteAccount(id: "a")
            #expect(db.getAllAccounts().map(\.id) == ["b"])
        }
    }

    @Test func deleteUnknownAccountIsNoOp() throws {
        try withDatabase { db, _ in
            db.saveAccount(account(id: "a", name: "a"))
            db.deleteAccount(id: "nope")
            #expect(db.getAllAccounts().count == 1)
        }
    }

    @Test func deleteByRemoteNameRemovesMatchingRow() throws {
        try withDatabase { db, _ in
            db.saveAccount(account(id: "a", name: "alpha", createdAt: Date(timeIntervalSince1970: 1)))
            db.saveAccount(account(id: "b", name: "beta", createdAt: Date(timeIntervalSince1970: 2)))
            db.deleteAccountByRemoteName("alpha")
            #expect(db.getAllAccounts().map(\.name) == ["beta"])
            db.deleteAccountByRemoteName("does-not-exist")
            #expect(db.getAllAccounts().count == 1)
        }
    }

    @Test func nameCanBeReusedAfterDeletion() throws {
        try withDatabase { db, _ in
            db.saveAccount(account(id: "old", name: "reused"))
            db.deleteAccount(id: "old")
            db.saveAccount(account(id: "new", name: "reused"))
            #expect(db.getAllAccounts().map(\.id) == ["new"])
        }
    }

    // MARK: Concurrency

    @Test func concurrentWritesAreSerialised() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = AccountDatabase(dbPath: dir.appendingPathComponent("c.db").path)

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    db.saveAccount(RemoteAccount(id: "id-\(i)", name: "name-\(i)",
                                                 provider: "drive", mountPath: "/tmp/\(i)"))
                }
            }
        }
        #expect(db.getAllAccounts().count == 50)
    }
}
