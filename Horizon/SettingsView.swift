//
//  SettingsView.swift
//  Horizon
//
//  Created by Horizon on 29/10/26.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var driveManager: DriveManager
    @EnvironmentObject var windowManager: WindowManager

    enum SettingsTab: String, CaseIterable, Identifiable {
        case accounts = "Accounts"
        case preferences = "General"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .accounts: return "person.crop.circle.badge.plus"
            case .preferences: return "gearshape"
            case .about: return "info.circle"
            }
        }
    }

    @State private var selectedTab: SettingsTab = .accounts
    @State private var accountToDelete: RemoteAccount? = nil
    @State private var showDeleteConfirmation = false
    @State private var accountToLogout: RemoteAccount? = nil
    @State private var showLogoutConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar with Tabs & Close button
            HStack(spacing: 12) {
                // Tab Picker
                HStack(spacing: 4) {
                    ForEach(SettingsTab.allCases) { tab in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tab.icon)
                                Text(tab.rawValue)
                            }
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selectedTab == tab ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 18)

                Spacer()

                Button {
                    windowManager.closeWindow()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 14)
            }
            .frame(height: 48)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))

            Divider()

            // Tab Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    switch selectedTab {
                    case .accounts:
                        accountsTabView
                    case .preferences:
                        preferencesTabView
                    case .about:
                        aboutTabView
                    }
                }
                .padding(24)
            }

            Divider()

            // Footer
            HStack {
                Text(driveManager.state.statusTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Done") {
                    windowManager.closeWindow()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 680, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Delete Connection?", isPresented: $showDeleteConfirmation, presenting: accountToDelete) { acc in
            Button("Delete Connection", role: .destructive) {
                Task {
                    await driveManager.deleteAccount(acc)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { acc in
            Text("Are you sure you want to remove '\(acc.displayTitle)'? Horizon will unmount this drive and remove its configuration.")
        }
        .alert("Log Out of Account?", isPresented: $showLogoutConfirmation, presenting: accountToLogout) { acc in
            Button("Log Out", role: .destructive) {
                Task {
                    await driveManager.logoutAccount(acc)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { acc in
            Text("This will revoke the login session for '\(acc.displayTitle)' and unmount the volume.")
        }
    }

    // MARK: - Accounts Tab

    private var accountsTabView: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected Accounts")
                        .font(.system(size: 16, weight: .bold))
                    Text("Manage cloud drives mounted in Finder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !driveManager.isAuthenticating {
                    Button {
                        Task {
                            _ = await driveManager.startGoogleDriveConnection()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                            Text("Add Account")
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Authentication in progress notification
            if driveManager.isAuthenticating {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Authorizing new account in browser...")
                            .font(.system(size: 13, weight: .medium))
                        Text("Complete the sign-in prompt in your web browser.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Cancel") {
                        driveManager.cancelAuthentication()
                    }
                    .controlSize(.small)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.1))
                )
            }

            // Authentication error if any
            if let err = driveManager.authError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") {
                        driveManager.authError = nil
                    }
                    .font(.caption2)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.red.opacity(0.1))
                )
            }

            // List of Accounts
            if driveManager.accounts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.xmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text("No accounts connected yet.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    Button("Connect Google Drive") {
                        Task {
                            _ = await driveManager.startGoogleDriveConnection()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(driveManager.accounts) { account in
                        accountRow(account: account)
                    }
                }
            }

            // Add Account Card
            VStack(alignment: .leading, spacing: 10) {
                Text("Add New Connection")
                    .font(.system(size: 13, weight: .semibold))

                HStack {
                    GoogleDriveLogoView(size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Google Drive")
                            .font(.system(size: 13, weight: .medium))
                        Text("Connect another personal or Google Workspace account")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        Task {
                            _ = await driveManager.startGoogleDriveConnection()
                        }
                    } label: {
                        Text("Connect")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(driveManager.isAuthenticating)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
            .padding(.top, 8)
        }
    }

    private func accountRow(account: RemoteAccount) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                GoogleDriveLogoView(size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(account.displayTitle)
                            .font(.system(size: 14, weight: .semibold))

                        // Status pill
                        Circle()
                            .fill(driveManager.state.isConnected ? Color.green : Color.secondary)
                            .frame(width: 7, height: 7)

                        Text(driveManager.state.isConnected ? "Mounted" : "Disconnected")
                            .font(.caption2)
                            .foregroundStyle(driveManager.state.isConnected ? .green : .secondary)
                    }

                    Text("Mount Location: \(account.mountPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Actions
                HStack(spacing: 8) {
                    if driveManager.state.isConnected {
                        Button {
                            driveManager.openInFinder()
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 12))
                        }
                        .help("Open in Finder")
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Disconnect") {
                            driveManager.disconnect()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button("Connect") {
                            driveManager.connect()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    // Logout Button
                    Button {
                        accountToLogout = account
                        showLogoutConfirmation = true
                    } label: {
                        Text("Logout")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    // Delete Connection Button
                    Button {
                        accountToDelete = account
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                    .help("Delete Connection")
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Preferences Tab

    private var preferencesTabView: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("General Preferences")
                    .font(.system(size: 16, weight: .bold))
                Text("System behavior and storage settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                // Launch at Login
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                            .font(.system(size: 13, weight: .medium))
                        Text("Automatically start Horizon in the menu bar when your Mac boots.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { driveManager.isLaunchAtLoginEnabled },
                        set: { _ in driveManager.toggleLaunchAtLogin() }
                    ))
                    .toggleStyle(.switch)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )

                // Cache Management
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cache Storage")
                            .font(.system(size: 13, weight: .medium))
                        Text(driveManager.cacheDir)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Clear Cache") {
                        driveManager.clearCache()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )

                // Logs
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diagnostics & Logs")
                            .font(.system(size: 13, weight: .medium))
                        Text("View system logs for debugging and rclone events.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Open Logs") {
                        driveManager.openLogs()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
        }
    }

    // MARK: - About Tab

    private var aboutTabView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 20)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)

                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .cornerRadius(12)
                } else {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue)
                }
            }

            VStack(spacing: 4) {
                Text("Horizon")
                    .font(.system(size: 20, weight: .bold))
                Text("Version 1.0 (Build 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Native Cloud Storage Streaming for macOS.\nStream Google Drive directly in Finder with zero disk consumption.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
    }
}
