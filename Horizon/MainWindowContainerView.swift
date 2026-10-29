//
//  MainWindowContainerView.swift
//  Horizon
//
//  Created by Horizon on 29/10/26.
//

import SwiftUI

struct MainWindowContainerView: View {
    @EnvironmentObject var windowManager: WindowManager
    @EnvironmentObject var driveManager: DriveManager

    var body: some View {
        Group {
            switch windowManager.currentRoute {
            case .setup:
                SetupView()
            case .settings:
                SettingsView()
            }
        }
    }
}
