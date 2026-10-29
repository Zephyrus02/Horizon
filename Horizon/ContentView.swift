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
    @State private var showAddAccountSheet = false

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

                    Text(statusSummaryText)
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

            // Accounts List (all connections shown simultaneously)
            if driveManager.accounts.isEmpty {
                VStack(spacing: 12) {
                    Text("No Accounts Connected")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    Button {
                        showAddAccountSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("Connect Cloud Drive")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            } else if driveManager.accounts.count <= 3 {
                // When 1-3 accounts, use direct VStack so MenuBarExtra calculates intrinsic fittingSize correctly without collapsing
                VStack(spacing: 8) {
                    ForEach(driveManager.accounts) { account in
                        accountCard(for: account)
                    }
                }
            } else {
                // When more than 3 accounts, provide a fixed explicit height so ScrollView does not collapse to 0 in AppKit popover
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 8) {
                        ForEach(driveManager.accounts) { account in
                            accountCard(for: account)
                        }
                    }
                    .padding(.trailing, 2)
                }
                .frame(height: 250)
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

            // Quick Actions: Add Connection & Settings
            HStack(spacing: 8) {
                Button {
                    showAddAccountSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("Add Connection")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    WindowManager.shared.showSettings()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "gearshape")
                        Text("Settings...")
                    }
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

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
        .frame(width: 340)
        .onAppear {
            driveManager.refreshAccounts()
        }
        .sheet(isPresented: $showAddAccountSheet) {
            AddConnectionView()
                .environmentObject(driveManager)
        }
    }

    private var statusSummaryText: String {
        if driveManager.accounts.isEmpty {
            return "No Accounts"
        }
        let total = driveManager.accounts.count
        let connected = driveManager.connectedCount
        if total == 1 {
            return driveManager.state.statusTitle
        }
        return "\(connected)/\(total) Connected"
    }

    private func accountCard(for account: RemoteAccount) -> some View {
        let accountState = driveManager.stateForAccount(account)
        let isSyncing = driveManager.isAccountSyncing(account)
        let syncText = driveManager.formattedLastSync(for: account)

        return VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ProviderLogoView(provider: account.provider, size: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    Text(account.mountPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(accountState.statusColor)
                            .frame(width: 5, height: 5)
                        Text(isSyncing ? "Syncing..." : (accountState.isConnected ? syncText : accountState.statusTitle))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 1)
                }

                Spacer(minLength: 6)

                Toggle(isOn: Binding(
                    get: {
                        accountState.isConnected || accountState == .connecting
                    },
                    set: { _ in
                        driveManager.toggleAccountConnection(account)
                    }
                )) {
                    EmptyView()
                }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(accountState.isTransitioning)
            }

            // Quick actions per account when connected
            if accountState.isConnected {
                HStack(spacing: 6) {
                    Button {
                        driveManager.openAccountInFinder(account)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text("Open in Finder")
                            Image(systemName: "arrow.up.forward")
                                .font(.caption2)
                        }
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        driveManager.syncAccount(account)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .rotationEffect(.degrees(isSyncing ? 360 : 0))
                                .animation(isSyncing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isSyncing)
                            Text(isSyncing ? "Syncing" : "Sync")
                        }
                        .font(.system(size: 11))
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isSyncing)
                    .help("Force immediate refresh from cloud")
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(driveManager: DriveManager.shared)
    }
}
