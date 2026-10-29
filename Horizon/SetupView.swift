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

    var body: some View {
        VStack(spacing: 0) {
            // Top Window Bar with step dots & close button
            HStack {
                // Step Indicator Pills
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

            // Main Content Area
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
        .frame(width: 640, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Step 1: Welcome View

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Spacer()

            // App Icon with smooth gradient border
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

                Text("Stream your cloud storage directly in Finder with zero disk overhead.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            // Feature Highlights
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(
                    icon: "folder.badge.gearshape",
                    iconColor: .blue,
                    title: "Native Finder Integration",
                    subtitle: "Browse, open, and modify cloud files exactly like a local volume."
                )

                FeatureRow(
                    icon: "bolt.fill",
                    iconColor: .orange,
                    title: "On-Demand Streaming",
                    subtitle: "Intelligently caches what you access without occupying your local SSD."
                )

                FeatureRow(
                    icon: "lock.shield.fill",
                    iconColor: .green,
                    title: "Direct & Zero-Config",
                    subtitle: "Log in with your Google account in your browser. No API keys needed."
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

            // Continue Button
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
        VStack(spacing: 20) {
            Spacer(minLength: 16)

            VStack(spacing: 6) {
                Text("Connect Your Storage")
                    .font(.system(size: 24, weight: .bold))

                Text("Choose a cloud provider to mount as a local drive on your Mac.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                // Google Drive Row (Primary)
                HStack(spacing: 14) {
                    GoogleDriveLogoView(size: 32)
                        .frame(width: 38, height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Google Drive")
                            .font(.system(size: 15, weight: .semibold))

                        Text("Stream your personal or Google Workspace files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if driveManager.isAuthenticating {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Waiting for login...")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)

                            Button("Cancel") {
                                driveManager.cancelAuthentication()
                            }
                            .controlSize(.small)
                        }
                    } else if driveManager.state.isConnected || driveManager.hasConfiguredAccounts {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Connected")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.green)
                        }
                    } else {
                        Button {
                            Task {
                                let success = await driveManager.startGoogleDriveConnection()
                                if success {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        currentStep = .complete
                                    }
                                }
                            }
                        } label: {
                            Text("Connect")
                                .fontWeight(.semibold)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                        )
                )

                // Microsoft OneDrive (Coming Soon)
                HStack(spacing: 14) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue.opacity(0.5))
                        .frame(width: 38, height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Microsoft OneDrive")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text("Personal, School, or Business accounts")
                            .font(.caption)
                            .foregroundStyle(.secondary.opacity(0.7))
                    }

                    Spacer()

                    Text("Coming Soon")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.12))
                        )
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                )

                // Dropbox (Coming Soon)
                HStack(spacing: 14) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue.opacity(0.5))
                        .frame(width: 38, height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dropbox")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text("Sync Dropbox storage into local Finder")
                            .font(.caption)
                            .foregroundStyle(.secondary.opacity(0.7))
                    }

                    Spacer()

                    Text("Coming Soon")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.12))
                        )
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                )
            }
            .padding(.horizontal, 48)

            // Authentication status / error callout
            if let error = driveManager.authError {
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
            } else if driveManager.isAuthenticating {
                HStack(spacing: 8) {
                    Image(systemName: "safari")
                        .foregroundStyle(Color.accentColor)
                    Text("Check your web browser to approve Google Drive access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 48)
            } else {
                Text("Clicking Connect will open your browser to log in with your Google account. No API keys required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 56)
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
                    Button("Next") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            currentStep = .complete
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Step 3: Complete View

    private var completeView: some View {
        VStack(spacing: 20) {
            Spacer()

            // Big checkmark
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 90, height: 90)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 8) {
                Text("You're All Set!")
                    .font(.system(size: 26, weight: .bold))

                let targetMount = driveManager.activeMountPath
                Text("Your Google Drive is mounted at \(targetMount) and Horizon is now running in your menu bar.")
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
                        Text("Finish & Start Horizon")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 12)

            Spacer()
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 24)
    }
}

// MARK: - Feature Row Component

struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 24, height: 24)
                .padding(.top, 2)

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
