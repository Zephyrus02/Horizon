//
//  HorizonApp.swift
//  Horizon
//
//  Created by Aneesh on 29/10/26.
//

import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let driveManagerProvider: () -> DriveManager
    private let presentSetup: () -> Void

    /// Used by `NSApplicationDelegateAdaptor`: wires the live singletons.
    override init() {
        self.driveManagerProvider = { DriveManager.shared }
        self.presentSetup = { WindowManager.shared.showSetup() }
        super.init()
    }

    init(driveManager: DriveManager, presentSetup: @escaping () -> Void) {
        self.driveManagerProvider = { driveManager }
        self.presentSetup = presentSetup
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let driveManager = driveManagerProvider()
        let presentSetup = self.presentSetup

        if !driveManager.hasCompletedOnboarding || !driveManager.hasConfiguredAccounts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                presentSetup()
            }
        } else {
            NSApp.setActivationPolicy(.accessory)
            if driveManager.activeAccount != nil && !driveManager.state.isConnected {
                driveManager.connect()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        driveManagerProvider().disconnectSync()
    }
}

@main
struct HorizonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var driveManager = DriveManager.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView(driveManager: driveManager)
        } label: {
            if let menuBarImage = NSImage(named: "MenuBarIcon") {
                let _ = menuBarImage.isTemplate = true
                Image(nsImage: menuBarImage)
            } else {
                Image(systemName: driveManager.state.isConnected ? "cloud.fill" : "cloud")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
