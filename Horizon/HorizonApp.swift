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

