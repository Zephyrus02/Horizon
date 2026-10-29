//
//  WindowManager.swift
//  Horizon
//
//  Created by Horizon on 29/10/26.
//

import AppKit
import SwiftUI

@MainActor
final class WindowManager: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = WindowManager()

    enum WindowRoute: Equatable {
        case setup
        case settings
    }

    @Published var currentRoute: WindowRoute = .setup

    private var window: NSWindow?

    func showSetup() {
        currentRoute = .setup
        presentWindow(width: 640, height: 480)
    }

    func showSettings() {
        currentRoute = .settings
        presentWindow(width: 680, height: 500)
    }

    func closeWindow() {
        window?.close()
    }

    private func presentWindow(width: CGFloat, height: CGFloat) {
        // Switch to regular app so the window gets full focus and dock/app switching
        NSApp.setActivationPolicy(.regular)

        if let existing = window {
            existing.setContentSize(NSSize(width: width, height: height))
            existing.center()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let mainView = MainWindowContainerView()
            .environmentObject(self)
            .environmentObject(DriveManager.shared)

        let hostingController = NSHostingController(rootView: mainView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Horizon"
        newWindow.titleVisibility = .hidden
        newWindow.titlebarAppearsTransparent = true
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        newWindow.isMovableByWindowBackground = true
        newWindow.setContentSize(NSSize(width: width, height: height))
        newWindow.center()
        newWindow.delegate = self
        newWindow.backgroundColor = .windowBackgroundColor
        newWindow.isReleasedWhenClosed = false

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.window = nil
            // Switch back to accessory mode so app lives purely in the menu bar
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
