//
//  WindowAndAppTests.swift
//  HorizonTests
//
//  WindowManager routing/window lifecycle and the AppDelegate launch/terminate logic.
//

import Testing
import AppKit
import SwiftUI
@testable import Horizon

@MainActor
@Suite("WindowManager", .serialized)
struct WindowManagerTests {

    /// Windows created while `body` runs.
    private func newWindows(during body: () -> Void) -> [NSWindow] {
        let before = Set(NSApp.windows.map { ObjectIdentifier($0) })
        body()
        return NSApp.windows.filter { !before.contains(ObjectIdentifier($0)) }
    }

    @Test func routesAreEquatable() {
        #expect(WindowManager.WindowRoute.setup == .setup)
        #expect(WindowManager.WindowRoute.setup != .settings)
    }

    @Test func startsOnSetupRoute() {
        #expect(WindowManager().currentRoute == .setup)
    }

    @Test func showSettingsCreatesConfiguredWindow() {
        let manager = WindowManager()
        let windows = newWindows { manager.showSettings() }
        defer { manager.closeWindow() }

        #expect(manager.currentRoute == .settings)
        #expect(windows.count == 1)
        let window = windows[0]
        #expect(window.title == "Horizon")
        #expect(window.titleVisibility == .hidden)
        #expect(window.titlebarAppearsTransparent)
        #expect(window.isMovableByWindowBackground)
        #expect(!window.isReleasedWhenClosed)
        #expect(window.styleMask.contains(.closable))
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.delegate === manager)
        #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 680, height: 500))
        #expect(NSApp.activationPolicy() == .regular)
    }

    @Test func showSetupUsesSetupSize() {
        let manager = WindowManager()
        let windows = newWindows { manager.showSetup() }
        defer { manager.closeWindow() }

        #expect(manager.currentRoute == .setup)
        #expect(windows.count == 1)
        #expect(windows[0].contentRect(forFrameRect: windows[0].frame).size == NSSize(width: 640, height: 480))
    }

    @Test func switchingRoutesReusesTheSameWindow() {
        let manager = WindowManager()
        let first = newWindows { manager.showSetup() }
        defer { manager.closeWindow() }

        let created = newWindows { manager.showSettings() }
        #expect(created.isEmpty)                         // no second window
        #expect(manager.currentRoute == .settings)
        #expect(first.count == 1)
        #expect(first[0].contentRect(forFrameRect: first[0].frame).size == NSSize(width: 680, height: 500))
    }

    @Test func closingWindowRestoresAccessoryPolicyAndAllowsRecreation() async {
        let manager = WindowManager()
        _ = newWindows { manager.showSettings() }

        manager.closeWindow()
        let reverted = await waitUntil { NSApp.activationPolicy() == .accessory }
        #expect(reverted)

        // After close the manager forgets the window, so a new one is built.
        let again = newWindows { manager.showSetup() }
        #expect(again.count == 1)
        manager.closeWindow()
    }

    @Test func closeWindowWithoutWindowIsSafe() {
        WindowManager().closeWindow()
    }

    @Test func sharedInstanceIsSingleton() {
        #expect(WindowManager.shared === WindowManager.shared)
    }

    @Test func mainWindowContainerRendersEachRoute() {
        let drive = DriveManager.shared
        for route in [WindowManager.WindowRoute.setup, .settings] {
            let manager = WindowManager()
            manager.currentRoute = route
            let size = render(
                MainWindowContainerView()
                    .environmentObject(manager)
                    .environmentObject(drive),
                width: 700, height: 520
            )
            #expect(size.width > 0 && size.height > 0)
        }
    }
}

@MainActor
@Suite("AppDelegate", .serialized)
struct AppDelegateTests {

    @Test func firstLaunchWithoutAccountsPresentsSetup() async throws {
        try await withHarness { h in
            let presented = Locked<Int>(0)
            let delegate = AppDelegate(driveManager: h.manager) { presented.mutate { $0 += 1 } }

            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

            #expect(await waitUntil { presented.value == 1 })
        }
    }

    @Test func accountsWithoutCompletedOnboardingStillPresentSetup() async throws {
        let account = RemoteAccount(name: "a", provider: "drive", mountPath: "/tmp/horizon-test-a")
        try await withHarness(preloadedAccounts: [account]) { h in
            h.manager.hasCompletedOnboarding = false
            let presented = Locked<Int>(0)
            let delegate = AppDelegate(driveManager: h.manager) { presented.mutate { $0 += 1 } }
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            #expect(await waitUntil { presented.value == 1 })
        }
    }

    @Test func onboardedUserWithoutAccountsPresentsSetup() async throws {
        try await withHarness { h in
            h.manager.hasCompletedOnboarding = true
            let presented = Locked<Int>(0)
            let delegate = AppDelegate(driveManager: h.manager) { presented.mutate { $0 += 1 } }
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            #expect(await waitUntil { presented.value == 1 })
        }
    }

    @Test func onboardedUserWithDisconnectedAccountAutoConnects() async throws {
        let account = RemoteAccount(id: "auto", name: "auto", provider: "drive", mountPath: "/tmp/horizon-test-auto")
        try await withHarness(preloadedAccounts: [account]) { h in
            h.manager.hasCompletedOnboarding = true
            let presented = Locked<Int>(0)
            let delegate = AppDelegate(driveManager: h.manager) { presented.mutate { $0 += 1 } }

            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

            #expect(h.manager.accountStates["auto"] == .connecting)   // connect() was invoked
            try await Task.sleep(nanoseconds: 200_000_000)
            #expect(presented.value == 0)                              // setup is not shown
        }
    }

    @Test func alreadyConnectedAccountIsNotReconnected() async throws {
        let account = RemoteAccount(id: "up", name: "up", provider: "drive", mountPath: "/tmp/horizon-test-up")
        try await withHarness(preloadedAccounts: [account], mountedPaths: ["/tmp/horizon-test-up"]) { h in
            h.manager.hasCompletedOnboarding = true
            #expect(h.manager.state.isConnected)
            let delegate = AppDelegate(driveManager: h.manager) {}
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            #expect(h.manager.accountStates["up"] == .connected)
            #expect(!h.rcloneInvocations.contains { $0.hasPrefix("nfsmount") })
        }
    }

    @Test func terminationUnmountsAllDrives() async throws {
        let a = RemoteAccount(id: "a", name: "a", provider: "drive", mountPath: "/tmp/horizon-test-term-a")
        let b = RemoteAccount(id: "b", name: "b", provider: "drive", mountPath: "/tmp/horizon-test-term-b")
        try await withHarness(preloadedAccounts: [a, b]) { h in
            let delegate = AppDelegate(driveManager: h.manager) {}
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            #expect(Set(h.mounts.unmountCalls.value) == ["/tmp/horizon-test-term-a", "/tmp/horizon-test-term-b"])
        }
    }

    @Test func defaultInitialiserWiresTheLiveSingletons() {
        // Constructing must not launch anything; it only captures the live providers.
        _ = AppDelegate()
    }

    @Test func appSceneBodyBuilds() {
        _ = HorizonApp().body
    }
}
