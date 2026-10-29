//
//  HorizonApp.swift
//  Horizon
//
//  Created by Aneesh on 29/10/26.
//

import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let driveManager = DriveManager.shared

        if !driveManager.hasCompletedOnboarding || !driveManager.hasConfiguredAccounts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                WindowManager.shared.showSetup()
            }
        } else {
            NSApp.setActivationPolicy(.accessory)
            if driveManager.activeAccount != nil && !driveManager.state.isConnected {
                driveManager.connect()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DriveManager.shared.disconnectSync()
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
