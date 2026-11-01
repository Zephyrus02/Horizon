//
//  ViewTests.swift
//  HorizonTests
//
//  Renders every SwiftUI screen in each of its states inside an AppKit hosting view.
//  This verifies the view bodies build and lay out for all model states and exercises the
//  view-logic branches (empty/1-3/4+ accounts, error banners, tabs, wizard steps, …).
//

import Testing
import SwiftUI
import AppKit
@testable import Horizon

/// Hosts `view` in an off-screen window, lays it out and returns its fitting size.
@MainActor
@discardableResult
func render<V: View>(_ view: V, width: CGFloat = 400, height: CGFloat = 600) -> CGSize {
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(x: 0, y: 0, width: width, height: height)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    host.display()
    // Let onAppear / state updates settle.
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    host.layoutSubtreeIfNeeded()
    let size = host.fittingSize
    window.contentView = nil
    window.close()
    return size
}

@MainActor
private func seeded(_ h: TestHarness, states: [(String, String, DriveState)]) -> [RemoteAccount] {
    var accounts: [RemoteAccount] = []
    for (i, entry) in states.enumerated() {
        let (name, provider, state) = entry
        let account = h.makeAccount(name: name, displayName: name.capitalized, provider: provider,
                                    createdAt: Date(timeIntervalSince1970: Double(i + 1)))
        h.database.saveAccount(account)
        if state == .connected { h.mounts.mount(account.mountPath) }
        accounts.append(account)
    }
    h.manager.refreshAccounts()
    for (account, entry) in zip(accounts, states) where entry.2 != .connected && entry.2 != .disconnected {
        h.manager.accountStates[account.id] = entry.2
    }
    h.manager.updateOverallState()
    return accounts
}

// MARK: - Menu bar popover

@MainActor
@Suite("ContentView (menu bar popover)")
struct ContentViewTests {

    @Test func rendersEmptyState() async throws {
        try await withHarness { h in
            let size = render(ContentView(driveManager: h.manager))
            #expect(size.width == 340)
            #expect(size.height > 100)
        }
    }

    @Test("renders 1…3 accounts as an inline list and 4+ in a scroll view", arguments: [1, 2, 3, 4, 6])
    func rendersAccountCounts(count: Int) async throws {
        try await withHarness { h in
            let specs = (0..<count).map { ("acct\($0)", ["drive", "onedrive", "dropbox"][$0 % 3], DriveState.disconnected) }
            _ = seeded(h, states: specs)
            let size = render(ContentView(driveManager: h.manager))
            #expect(size.width == 340)
            if count > 3 {
                // Scrolling list has a fixed 250pt height for the list portion.
                #expect(size.height > 250)
            }
        }
    }

    @Test func rendersEveryAccountState() async throws {
        try await withHarness { h in
            _ = seeded(h, states: [
                ("up", "drive", .connected),
                ("busy", "onedrive", .connecting),
                ("closing", "dropbox", .disconnecting),
                ("broken", "drive", .error("nope")),
            ])
            _ = render(ContentView(driveManager: h.manager))
        }
    }

    @Test func rendersSyncingAccount() async throws {
        try await withHarness { h in
            let accounts = seeded(h, states: [("sync", "drive", .connected)])
            h.manager.accountSyncing[accounts[0].id] = true
            h.manager.accountLastSync[accounts[0].id] = Date()
            _ = render(ContentView(driveManager: h.manager))
        }
    }

    @Test func rendersErrorBanner() async throws {
        try await withHarness { h in
            h.manager.errorMessage = "Something went wrong while mounting"
            let withError = render(ContentView(driveManager: h.manager))
            h.manager.errorMessage = nil
            let without = render(ContentView(driveManager: h.manager))
            #expect(withError.height > without.height)
        }
    }

    @Test("status summary text", arguments: [
        (0, 0, "No Accounts"),
        (1, 0, "Disconnected"),
        (1, 1, "Connected"),
        (2, 0, "0/2 Connected"),
        (3, 2, "2/3 Connected"),
    ])
    func statusSummary(total: Int, connected: Int, expected: String) async throws {
        try await withHarness { h in
            let specs = (0..<total).map { i in
                ("s\(i)", "drive", i < connected ? DriveState.connected : DriveState.disconnected)
            }
            _ = seeded(h, states: specs)
            #expect(ContentView(driveManager: h.manager).statusSummaryText == expected)
        }
    }

    @Test func previewProviderBuilds() {
        _ = ContentView_Previews.previews
    }
}

// MARK: - Settings

@MainActor
@Suite("SettingsView")
struct SettingsViewTests {

    @Test func tabMetadata() {
        let tabs = SettingsView.SettingsTab.allCases
        #expect(tabs.map(\.rawValue) == ["Accounts", "General", "About"])
        #expect(tabs.map(\.id) == ["Accounts", "General", "About"])
        #expect(tabs.map(\.icon) == ["person.crop.circle.badge.plus", "gearshape", "info.circle"])
    }

    @Test("renders each tab", arguments: SettingsView.SettingsTab.allCases)
    func rendersEachTab(tab: SettingsView.SettingsTab) async throws {
        try await withHarness { h in
            let size = render(
                SettingsView(initialTab: tab)
                    .environmentObject(h.manager)
                    .environmentObject(WindowManager()),
                width: 700, height: 520
            )
            #expect(size.width == 680)
            #expect(size.height == 500)
        }
    }

    @Test("accounts tab renders empty, populated and mixed-state lists", arguments: [0, 1, 3])
    func accountsTabWithAccounts(count: Int) async throws {
        try await withHarness { h in
            let kinds: [(String, String, DriveState)] = [
                ("one", "drive", .connected), ("two", "onedrive", .disconnected), ("three", "dropbox", .connecting),
            ]
            _ = seeded(h, states: Array(kinds.prefix(count)))
            _ = render(
                SettingsView(initialTab: .accounts)
                    .environmentObject(h.manager)
                    .environmentObject(WindowManager()),
                width: 700, height: 520
            )
        }
    }

    @Test func footerSummarisesMultipleDrives() async throws {
        try await withHarness { h in
            _ = seeded(h, states: [("a", "drive", .connected), ("b", "drive", .disconnected)])
            _ = render(SettingsView().environmentObject(h.manager).environmentObject(WindowManager()),
                       width: 700, height: 520)
        }
    }

    @Test func previewProviderBuilds() {
        _ = SettingsView_Previews.previews
    }
}

// MARK: - Setup wizard

@MainActor
@Suite("SetupView")
struct SetupViewTests {

    @Test func stepsAreOrdered() {
        #expect(SetupView.SetupStep.allCases.map(\.rawValue) == [0, 1, 2])
        #expect(SetupView.SetupStep.welcome.rawValue < SetupView.SetupStep.connect.rawValue)
        #expect(SetupView.SetupStep.connect.rawValue < SetupView.SetupStep.complete.rawValue)
    }

    @Test("renders each step", arguments: SetupView.SetupStep.allCases)
    func rendersEachStep(step: SetupView.SetupStep) async throws {
        try await withHarness { h in
            let size = render(
                SetupView(initialStep: step)
                    .environmentObject(h.manager)
                    .environmentObject(WindowManager()),
                width: 660, height: 500
            )
            #expect(size.width == 640)
            #expect(size.height == 490)
        }
    }

    @Test func connectStepShowsAuthProgressAndErrors() async throws {
        try await withHarness { h in
            h.manager.isAuthenticating = true
            _ = render(SetupView(initialStep: .connect).environmentObject(h.manager).environmentObject(WindowManager()),
                       width: 660, height: 500)

            h.manager.isAuthenticating = false
            h.manager.authError = "Authentication failed or was cancelled."
            _ = render(SetupView(initialStep: .connect).environmentObject(h.manager).environmentObject(WindowManager()),
                       width: 660, height: 500)
        }
    }

    @Test func connectStepOffersSkipWhenAccountsExist() async throws {
        try await withHarness { h in
            _ = seeded(h, states: [("have", "drive", .connected)])
            _ = render(SetupView(initialStep: .connect).environmentObject(h.manager).environmentObject(WindowManager()),
                       width: 660, height: 500)
        }
    }

    @Test func completeStepPluralisesConnectionCount() async throws {
        try await withHarness { h in
            _ = seeded(h, states: [("a", "drive", .connected)])
            _ = render(SetupView(initialStep: .complete).environmentObject(h.manager).environmentObject(WindowManager()),
                       width: 660, height: 500)
            _ = seeded(h, states: [("a", "drive", .connected), ("b", "dropbox", .connected)])
            _ = render(SetupView(initialStep: .complete).environmentObject(h.manager).environmentObject(WindowManager()),
                       width: 660, height: 500)
        }
    }
}

// MARK: - Add connection sheet

@MainActor
@Suite("AddConnectionView")
struct AddConnectionViewTests {

    @Test func rendersIdleState() async throws {
        try await withHarness { h in
            let size = render(AddConnectionView().environmentObject(h.manager), width: 500, height: 440)
            #expect(size.width == 480)
            #expect(size.height == 420)
        }
    }

    @Test func rendersAuthenticatingState() async throws {
        try await withHarness { h in
            h.manager.isAuthenticating = true
            _ = render(AddConnectionView().environmentObject(h.manager), width: 500, height: 440)
        }
    }

    @Test func rendersAuthError() async throws {
        try await withHarness { h in
            h.manager.authError = "invalid_grant"
            _ = render(AddConnectionView().environmentObject(h.manager), width: 500, height: 440)
        }
    }

    @Test func rendersWithExistingDriveAccounts() async throws {
        try await withHarness { h in
            _ = seeded(h, states: [("g1", "drive", .disconnected), ("g2", "drive", .disconnected)])
            _ = render(AddConnectionView(onComplete: {}).environmentObject(h.manager), width: 500, height: 440)
        }
    }
}

// MARK: - Provider logos

@MainActor
@Suite("Provider logos")
struct ProviderLogoTests {

    @Test("ProviderLogoView renders every provider", arguments: ["drive", "onedrive", "OneDrive", "dropbox", "DROPBOX", "unknown", ""])
    func providerLogoRenders(provider: String) {
        let size = render(ProviderLogoView(provider: provider, size: 32), width: 64, height: 64)
        #expect(size.width == 32)
        #expect(size.height == 32)
    }

    @Test func defaultLogoSizeIs24() {
        #expect(render(ProviderLogoView(provider: "drive"), width: 64, height: 64) == CGSize(width: 24, height: 24))
    }

    @Test("standalone logos honour their size", arguments: [12.0, 20.0, 48.0])
    func logosHonourSize(size: Double) {
        let s = CGFloat(size)
        #expect(render(GoogleDriveLogoView(size: s), width: 100, height: 100) == CGSize(width: s, height: s))
        #expect(render(OneDriveLogoView(size: s), width: 100, height: 100) == CGSize(width: s, height: s))
        #expect(render(DropboxLogoView(size: s), width: 100, height: 100) == CGSize(width: s, height: s))
    }

    @Test func logosHaveDefaultSize() {
        #expect(GoogleDriveLogoView().size == 24)
        #expect(OneDriveLogoView().size == 24)
        #expect(DropboxLogoView().size == 24)
    }
}
