//
//  ContentView.swift
//  Horizon
//
//  Created by Aneesh on 29/10/26.
//

import SwiftUI
import Combine

struct ContentView: View {
    @ObservedObject var driveManager: DriveManager

    var body: some View {
        VStack(spacing: 12) {
            // Header: App Title & Status Pill
            HStack(alignment: .center) {
                HStack(spacing: 7) {
                    if let nsImage = NSImage(named: "MenuBarIcon") {
                        Image(nsImage: nsImage)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                            .foregroundStyle(.primary)
                    } else {
                        Image(systemName: "cloud.fill")
                            .foregroundStyle(.blue)
                    }

                    Text("Horizon")
                        .font(.headline)
                        .fontWeight(.semibold)
                }

                Spacer()

                // Status Badge
                HStack(spacing: 5) {
                    Circle()
                        .fill(driveManager.state.statusColor)
                        .frame(width: 7, height: 7)

                    Text(driveManager.state.statusTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(driveManager.state.statusColor.opacity(0.12))
                )
            }

            Divider()

            // Main Account Card or Empty State
            if driveManager.accounts.isEmpty {
                VStack(spacing: 10) {
                    Text("No Accounts Connected")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    Button {
                        WindowManager.shared.showSetup()
                    } label: {
                        HStack(spacing: 6) {
                            GoogleDriveLogoView(size: 16)
                            Text("Set Up Google Drive")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            } else {
                VStack(spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        GoogleDriveLogoView(size: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(driveManager.activeAccount?.displayTitle ?? "Google Drive")
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)

                            Text(driveManager.activeMountPath)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle(isOn: Binding(
                            get: {
                                driveManager.state.isConnected || driveManager.state == .connecting
                            },
                            set: { shouldConnect in
                                if shouldConnect {
                                    driveManager.connect()
                                } else {
                                    driveManager.disconnect()
                                }
                            }
                        )) {
                            Text("Connect")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .toggleStyle(.switch)
                        .disabled(driveManager.state.isTransitioning)
                    }

                    // Transitioning indicator
                    if driveManager.state.isTransitioning {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(driveManager.state == .connecting ? "Mounting Google Drive..." : "Unmounting...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }

            // Error Notice (if any)
            if let error = driveManager.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.top, 2)

                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(3)

                    Spacer(minLength: 4)

                    Button {
                        driveManager.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.red.opacity(0.1))
                )
            }

            // Quick Actions (when connected)
            if driveManager.state.isConnected {
                Button(action: {
                    driveManager.openInFinder()
                }) {
                    HStack {
                        Image(systemName: "folder")
                        Text("Open in Finder")
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            // Settings Button
            Button(action: {
                WindowManager.shared.showSettings()
            }) {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Settings...")
                    Spacer()
                }
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Divider()

            // Footer Actions
            HStack {
                Button("View Logs") {
                    driveManager.openLogs()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Quit Horizon") {
                    driveManager.disconnectSync()
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(driveManager: DriveManager.shared)
    }
}
