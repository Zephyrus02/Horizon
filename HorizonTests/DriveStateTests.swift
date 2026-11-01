//
//  DriveStateTests.swift
//  HorizonTests
//
//  Tests for the pure model types: DriveState and RemoteAccount.
//

import Testing
import Foundation
import SwiftUI
@testable import Horizon

@Suite("DriveState")
struct DriveStateTests {

    static let allStates: [DriveState] = [
        .disconnected, .connecting, .connected, .disconnecting, .error("boom")
    ]

    @Test("isConnected is true only for .connected", arguments: allStates)
    func isConnected(state: DriveState) {
        #expect(state.isConnected == (state == .connected))
    }

    @Test("isError is true only for .error", arguments: allStates)
    func isError(state: DriveState) {
        if case .error = state {
            #expect(state.isError)
        } else {
            #expect(!state.isError)
        }
    }

    @Test("isTransitioning covers connecting and disconnecting only", arguments: allStates)
    func isTransitioning(state: DriveState) {
        let expected = (state == .connecting || state == .disconnecting)
        #expect(state.isTransitioning == expected)
    }

    @Test("statusTitle", arguments: [
        (DriveState.disconnected, "Disconnected"),
        (DriveState.connecting, "Connecting..."),
        (DriveState.connected, "Connected"),
        (DriveState.disconnecting, "Disconnecting..."),
        (DriveState.error("anything"), "Error"),
    ])
    func statusTitle(state: DriveState, title: String) {
        #expect(state.statusTitle == title)
    }

    @Test("statusColor", arguments: [
        (DriveState.disconnected, Color.secondary),
        (DriveState.connecting, Color.orange),
        (DriveState.disconnecting, Color.orange),
        (DriveState.connected, Color.green),
        (DriveState.error("x"), Color.red),
    ])
    func statusColor(state: DriveState, color: Color) {
        #expect(state.statusColor == color)
    }

    @Test func equatableComparesErrorPayload() {
        #expect(DriveState.error("a") == DriveState.error("a"))
        #expect(DriveState.error("a") != DriveState.error("b"))
        #expect(DriveState.error("a") != DriveState.disconnected)
        #expect(DriveState.connected != DriveState.connecting)
    }
}

@Suite("RemoteAccount")
struct RemoteAccountTests {

    @Test func initAppliesDefaults() {
        let account = RemoteAccount(name: "remote", provider: "drive", mountPath: "/mnt/x")
        #expect(!account.id.isEmpty)
        #expect(UUID(uuidString: account.id) != nil)
        #expect(account.displayName == "remote")           // falls back to name
        #expect(account.isConnected == false)
        #expect(account.autoConnect == true)
        #expect(account.accountName == nil)
        #expect(account.accountEmail == nil)
    }

    @Test func generatedIdsAreUnique() {
        let a = RemoteAccount(name: "a", provider: "drive", mountPath: "/a")
        let b = RemoteAccount(name: "a", provider: "drive", mountPath: "/a")
        #expect(a.id != b.id)
    }

    @Test func displayNameFallsBackToAccountNameThenName() {
        let withAccountName = RemoteAccount(name: "n", provider: "drive", accountName: "Acct", mountPath: "/m")
        #expect(withAccountName.displayName == "Acct")

        let explicit = RemoteAccount(name: "n", displayName: "Explicit", provider: "drive", accountName: "Acct", mountPath: "/m")
        #expect(explicit.displayName == "Explicit")
    }

    @Test func initStoresAllProvidedValues() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let account = RemoteAccount(
            id: "id-1", name: "n", displayName: "D", provider: "dropbox",
            accountName: "AN", accountEmail: "a@b.c", mountPath: "/m",
            isConnected: true, autoConnect: false, createdAt: date
        )
        #expect(account.id == "id-1")
        #expect(account.provider == "dropbox")
        #expect(account.accountName == "AN")
        #expect(account.accountEmail == "a@b.c")
        #expect(account.mountPath == "/m")
        #expect(account.isConnected)
        #expect(!account.autoConnect)
        #expect(account.createdAt == date)
    }

    @Test func displayTitlePrefersDisplayName() {
        let account = RemoteAccount(name: "n", displayName: "Shown", provider: "drive",
                                    accountName: "AN", accountEmail: "e@x.y", mountPath: "/m")
        #expect(account.displayTitle == "Shown")
    }

    @Test func displayTitleFallsBackThroughEmailAccountNameThenName() {
        var account = RemoteAccount(name: "raw", displayName: "x", provider: "drive",
                                    accountName: "AN", accountEmail: "e@x.y", mountPath: "/m")
        account.displayName = ""
        #expect(account.displayTitle == "e@x.y")

        account.accountEmail = ""
        #expect(account.displayTitle == "AN")

        account.accountEmail = nil
        #expect(account.displayTitle == "AN")

        account.accountName = ""
        #expect(account.displayTitle == "raw")

        account.accountName = nil
        #expect(account.displayTitle == "raw")
    }

    @Test("providerDisplayName", arguments: [
        ("drive", "Google Drive"),
        ("DRIVE", "Google Drive"),
        ("onedrive", "OneDrive"),
        ("OneDrive", "OneDrive"),
        ("dropbox", "Dropbox"),
        ("box", "Box"),
        ("s3", "S3"),
    ])
    func providerDisplayName(provider: String, expected: String) {
        let account = RemoteAccount(name: "n", provider: provider, mountPath: "/m")
        #expect(account.providerDisplayName == expected)
    }

    @Test func codableRoundTripPreservesEverything() throws {
        let original = RemoteAccount(
            id: "abc", name: "work", displayName: "Work", provider: "onedrive",
            accountName: "Person", accountEmail: "p@example.com", mountPath: "/Volumes/Work",
            isConnected: true, autoConnect: false,
            createdAt: Date(timeIntervalSince1970: 1_650_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteAccount.self, from: data)
        #expect(decoded == original)
    }

    @Test func equalityAndHashingConsiderAllFields() {
        let a = RemoteAccount(id: "1", name: "n", displayName: "d", provider: "drive", mountPath: "/m",
                              createdAt: Date(timeIntervalSince1970: 0))
        var b = a
        #expect(a == b)
        #expect(Set([a, b]).count == 1)

        b.mountPath = "/other"
        #expect(a != b)
        #expect(Set([a, b]).count == 2)
    }

    @Test func identifiableUsesId() {
        let account = RemoteAccount(id: "xyz", name: "n", provider: "drive", mountPath: "/m")
        #expect(account.id == "xyz")
    }
}
