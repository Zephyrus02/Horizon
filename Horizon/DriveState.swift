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
    var id: String { name }
    let name: String
    let provider: String
    var accountName: String?
    var accountEmail: String?
    var mountPath: String
    var isConnected: Bool = false

    var displayTitle: String {
        if let email = accountEmail, !email.isEmpty {
            return email
        }
        if let accName = accountName, !accName.isEmpty {
            return accName
        }
        if name == "gdrive" {
            return "Google Drive"
        }
        return "Google Drive (\(name))"
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
