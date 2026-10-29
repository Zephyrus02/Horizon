//
//  DriveState.swift
//  Horizon
//
//  Created by Horizon on 29/10/26.
//

import SwiftUI

enum DriveState: Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case error(String)

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    var isError: Bool {
        if case .error = self {
            return true
        }
        return false
    }

    var isTransitioning: Bool {
        switch self {
        case .connecting, .disconnecting:
            return true
        default:
            return false
        }
    }

    var statusTitle: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .disconnecting:
            return "Disconnecting..."
        case .error:
            return "Error"
        }
    }

    var statusColor: Color {
        switch self {
        case .disconnected:
            return .secondary
        case .connecting, .disconnecting:
            return .orange
        case .connected:
            return .green
        case .error:
            return .red
        }
    }
}

struct RemoteAccount: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var displayName: String
    var provider: String
    var mountPath: String
    var isConnected: Bool = false
    var autoConnect: Bool = true
    var createdAt: Date = Date()
    var accountName: String? = nil
    var accountEmail: String? = nil

    init(
        id: String = UUID().uuidString,
        name: String,
        displayName: String? = nil,
        provider: String,
        accountName: String? = nil,
        accountEmail: String? = nil,
        mountPath: String,
        isConnected: Bool = false,
        autoConnect: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName ?? (accountName ?? name)
        self.provider = provider
        self.accountName = accountName
        self.accountEmail = accountEmail
        self.mountPath = mountPath
        self.isConnected = isConnected
        self.autoConnect = autoConnect
        self.createdAt = createdAt
    }

    var displayTitle: String {
        if !displayName.isEmpty {
            return displayName
        }
        if let email = accountEmail, !email.isEmpty {
            return email
        }
        if let accName = accountName, !accName.isEmpty {
            return accName
        }
        return name
    }

    var providerDisplayName: String {
        switch provider.lowercased() {
        case "drive":
            return "Google Drive"
        case "onedrive":
            return "OneDrive"
        case "dropbox":
            return "Dropbox"
        default:
            return provider.capitalized
        }
    }
}
