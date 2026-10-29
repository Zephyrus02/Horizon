//
//  SetupView.swift
//  Horizon
//
//  Created by Horizon on 29/10/26.
//

import SwiftUI
import AppKit

struct SetupView: View {
    @EnvironmentObject var driveManager: DriveManager
    @EnvironmentObject var windowManager: WindowManager

    enum SetupStep: Int, CaseIterable {
        case welcome = 0
        case connect = 1
        case complete = 2
    }

    @State private var currentStep: SetupStep = .welcome
    @State private var connectionName: String = "Google Drive"
    @State private var mountPath: String = ("~/Google Drive" as NSString).expandingTildeInPath
    @State private var isCustomMount: Bool = false
    @State private var selectedProvider: String = "drive"
    @State private var isConnecting: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Top Window Bar with step dots & close button
            HStack {
                HStack(spacing: 6) {
                    ForEach(SetupStep.allCases, id: \.self) { step in
                        Capsule()
                            .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: step == currentStep ? 24 : 8, height: 6)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: currentStep)
                    }
                }
                .padding(.leading, 18)

                Spacer()

                Button {
                    driveManager.cancelAuthentication()
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
            .frame(height: 44)

            Divider()

            Group {
                switch currentStep {
                case .welcome:
                    welcomeView
                case .connect:
                    connectView
                case .complete:
                    completeView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 640, height: 490)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Step 1: Welcome View

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 80, height: 80)
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)

                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .cornerRadius(16)
                } else if let menuBar = NSImage(named: "MenuBarIcon") {
                    Image(nsImage: menuBar)
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.primary)
                } else {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                }
            }

            VStack(spacing: 8) {
                Text("Welcome to Horizon")
                    .font(.system(size: 26, weight: .bold))

                Text("Mount cloud storage directly into Finder with native two-way sync and SQLite metadata.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(
                    icon: "folder.badge.gearshape",
                    iconColor: .blue,
                    title: "Native Finder Integration",
                    subtitle: "Browse, open, and modify cloud files exactly like a local volume."
                )

                FeatureRow(
                    icon: "externaldrive.connected.to.line.below",
                    iconColor: .purple,
                    title: "Multi-Account Concurrent Mounts",
                    subtitle: "Mount personal and work cloud drives side by side simultaneously."
                )

                FeatureRow(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .orange,
                    title: "Instant Two-Way Synchronization",
                    subtitle: "Cloud edits appear locally within seconds, and Finder changes push instantly."
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )
            .padding(.horizontal, 48)

            Spacer()

            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        currentStep = .connect
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Get Started")
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Step 2: Connect Storage View

    private var connectView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)

            VStack(spacing: 4) {
                Text("Configure Cloud Connection")
                    .font(.system(size: 22, weight: .bold))

                Text("Assign your custom connection name and local mount folder.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                // Provider Selection
                HStack(spacing: 12) {
                    providerButton(id: "drive", title: "Google Drive")
                    providerButton(id: "onedrive", title: "OneDrive")
                    providerButton(id: "dropbox", title: "Dropbox")
                }

                // Connection Name Field
                VStack(alignment: .leading, spacing: 5) {
                    Text("Connection Name")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField("e.g. Work Drive, Personal Google Drive", text: $connectionName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: connectionName) { newName in
                            if !isCustomMount {
                                let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                                mountPath = clean.isEmpty ? ("~/CloudDrive" as NSString).expandingTildeInPath : (("~/\(clean)" as NSString).expandingTildeInPath)
                            }
                        }
                }

                // Mount Location Field
                VStack(alignment: .leading, spacing: 5) {
                    Text("Local Mount Folder")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("Folder path", text: $mountPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .onChange(of: mountPath) { _ in
                                isCustomMount = true
                            }

                        Button("Browse...") {
                            chooseFolder()
                        }
                        .controlSize(.small)
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .padding(.horizontal, 48)

            // Auth in progress or error
            if driveManager.isAuthenticating {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Opening browser for authorization... Please sign in.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        driveManager.cancelAuthentication()
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.1))
                )
                .padding(.horizontal, 48)
            } else if let error = driveManager.authError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.red.opacity(0.1))
                )
                .padding(.horizontal, 48)
            }

            Spacer()

            // Footer navigation
            HStack {
                Button("Back") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        currentStep = .welcome
                    }
                }
                .controlSize(.large)

                Spacer()

                if driveManager.hasConfiguredAccounts {
                    Button("Skip to Finish") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            currentStep = .complete
                        }
                    }
                    .controlSize(.large)
                }

                Button {
                    let name = connectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    isConnecting = true
                    Task {
                        let success = await driveManager.startConnection(
                            displayName: name,
                            mountPath: mountPath,
                            provider: selectedProvider
                        )
                        isConnecting = false
                        if success {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                currentStep = .complete
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(driveManager.isAuthenticating ? "Authenticating..." : "Connect Drive")
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(connectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || driveManager.isAuthenticating || isConnecting)
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 24)
        }
    }

    private func providerButton(id: String, title: String) -> some View {
        Button {
            selectedProvider = id
            if !isCustomMount {
                switch id {
                case "onedrive": connectionName = "OneDrive"
                case "dropbox": connectionName = "Dropbox"
                default: connectionName = "Google Drive"
                }
                mountPath = (("~/\(connectionName)" as NSString).expandingTildeInPath)
            }
        } label: {
            HStack(spacing: 8) {
                ProviderLogoView(provider: id, size: 20)
                Text(title)
                    .font(.system(size: 12, weight: selectedProvider == id ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selectedProvider == id ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(selectedProvider == id ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Mount Folder"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.mountPath = url.path
                self.isCustomMount = true
            }
        }
    }

    // MARK: - Step 3: Complete View

    private var completeView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 90, height: 90)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 8) {
                Text("Setup Complete!")
                    .font(.system(size: 26, weight: .bold))

                let count = driveManager.accounts.count
                Text(count > 1 ? "\(count) cloud connections are configured and ready in Horizon." : "Your drive is mounted and ready in Finder.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            HStack(spacing: 12) {
                Button {
                    driveManager.openInFinder()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text("Open in Finder")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    windowManager.closeWindow()
                } label: {
                    HStack(spacing: 6) {
                        Text("Start Horizon")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer()
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
