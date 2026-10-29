//
//  AddConnectionView.swift
//  Horizon
//
//  Created by Horizon on 29/10/26.
//

import SwiftUI
import AppKit

struct AddConnectionView: View {
    @EnvironmentObject var driveManager: DriveManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProvider: String = "drive"
    @State private var connectionName: String = ""
    @State private var mountPath: String = ""
    @State private var isCustomMountPath: Bool = false
    @State private var isSubmitting: Bool = false

    var onComplete: (() -> Void)? = nil

    private var defaultSuggestedName: String {
        switch selectedProvider {
        case "onedrive": return "OneDrive"
        case "dropbox": return "Dropbox"
        default:
            let existingDriveCount = driveManager.accounts.filter { $0.provider == "drive" }.count
            return existingDriveCount == 0 ? "Google Drive" : "Google Drive \(existingDriveCount + 1)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Text("Add Cloud Connection")
                    .font(.system(size: 15, weight: .bold))

                Spacer()

                Button {
                    driveManager.cancelAuthentication()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 1. Choose Provider
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cloud Provider")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            providerOption(id: "drive", title: "Google Drive")
                            providerOption(id: "onedrive", title: "OneDrive")
                            providerOption(id: "dropbox", title: "Dropbox")
                        }
                    }

                    // 2. Connection Name (User assigned)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Connection Name")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        TextField("e.g. Work Drive, Personal Google Drive", text: $connectionName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .onChange(of: connectionName) { newName in
                                if !isCustomMountPath {
                                    updateSuggestedMountPath(for: newName)
                                }
                            }

                        Text("This name will label your drive in Horizon and Finder.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // 3. Mount Location
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mount Location")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            TextField("Path to mount directory", text: $mountPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .onChange(of: mountPath) { _ in
                                    isCustomMountPath = true
                                }

                            Button("Browse...") {
                                chooseCustomFolder()
                            }
                            .controlSize(.small)
                        }

                        Text("Files in this cloud account will be accessed through this local folder.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Status / Progress indicator
                    if driveManager.isAuthenticating {
                        HStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.small)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Authorizing in your web browser...")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Please complete the sign-in prompt to authorize Horizon.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.accentColor.opacity(0.1))
                        )
                    }

                    // Error Notice
                    if let error = driveManager.authError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.red.opacity(0.1))
                        )
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer Actions
            HStack {
                Button("Cancel") {
                    driveManager.cancelAuthentication()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if driveManager.isAuthenticating {
                    Button("Cancel Sign-In") {
                        driveManager.cancelAuthentication()
                    }
                    .controlSize(.regular)
                } else {
                    Button {
                        submitConnection()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Sign In & Connect")
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(connectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 480, height: 420)
        .onAppear {
            if connectionName.isEmpty {
                connectionName = defaultSuggestedName
                updateSuggestedMountPath(for: connectionName)
            }
        }
    }

    private func providerOption(id: String, title: String) -> some View {
        Button {
            selectedProvider = id
            if !isCustomMountPath {
                connectionName = defaultSuggestedName
                updateSuggestedMountPath(for: connectionName)
            }
        } label: {
            HStack(spacing: 8) {
                ProviderLogoView(provider: id, size: 20)
                Text(title)
                    .font(.system(size: 12, weight: selectedProvider == id ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
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

    private func updateSuggestedMountPath(for name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanName.isEmpty {
            mountPath = ("~/CloudDrive" as NSString).expandingTildeInPath
        } else {
            mountPath = (("~/\(cleanName)" as NSString).expandingTildeInPath)
        }
    }

    private func chooseCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Mount Folder"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.mountPath = url.path
                self.isCustomMountPath = true
            }
        }
    }

    private func submitConnection() {
        let name = connectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let path = mountPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPath = path.isEmpty ? (("~/\(name)" as NSString).expandingTildeInPath) : path

        isSubmitting = true
        Task {
            let success = await driveManager.startConnection(
                displayName: name,
                mountPath: resolvedPath,
                provider: selectedProvider
            )
            isSubmitting = false
            if success {
                onComplete?()
                dismiss()
            }
        }
    }
}
