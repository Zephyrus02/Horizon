//
//  HorizonTests.swift
//  HorizonTests
//
//  Created by Aneesh on 29/10/26.
//

import Testing
import Foundation
@testable import Horizon

struct HorizonTests {

    @Test func testRemoteNameSanitization() async throws {
        #expect(DriveManager.sanitizeRemoteName("Work Drive") == "work_drive")
        #expect(DriveManager.sanitizeRemoteName("Personal & School Drive") == "personal_school_drive")
        #expect(DriveManager.sanitizeRemoteName("My-Storage_123") == "my-storage_123")
        #expect(DriveManager.sanitizeRemoteName("") == "cloud_drive")
    }

    @Test func testAccountDatabaseOperations() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDbPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db").path
        defer {
            try? FileManager.default.removeItem(atPath: testDbPath)
        }

        let db = AccountDatabase(dbPath: testDbPath)

        // 1. Initial should be empty
        #expect(db.getAllAccounts().isEmpty)

        // 2. Insert account
        let account1 = RemoteAccount(
            id: "acc_1",
            name: "work_drive",
            displayName: "Work Drive",
            provider: "drive",
            mountPath: "/tmp/Work Drive",
            isConnected: false,
            autoConnect: true
        )
        db.saveAccount(account1)

        var accounts = db.getAllAccounts()
        #expect(accounts.count == 1)
        #expect(accounts.first?.displayName == "Work Drive")
        #expect(accounts.first?.name == "work_drive")
        #expect(accounts.first?.isConnected == false)

        // 3. Update connection state
        db.updateConnectionStatus(id: "acc_1", isConnected: true)
        accounts = db.getAllAccounts()
        #expect(accounts.first?.isConnected == true)

        // 4. Insert second account
        let account2 = RemoteAccount(
            id: "acc_2",
            name: "personal_drive",
            displayName: "Personal Drive",
            provider: "onedrive",
            mountPath: "/tmp/Personal Drive",
            isConnected: false,
            autoConnect: true
        )
        db.saveAccount(account2)

        accounts = db.getAllAccounts()
        #expect(accounts.count == 2)

        // 5. Delete account
        db.deleteAccount(id: "acc_1")
        accounts = db.getAllAccounts()
        #expect(accounts.count == 1)
        #expect(accounts.first?.id == "acc_2")
    }
}
