//
//  ProviderLogoView.swift
//  Horizon
//
//  Created by Horizon on 29/10/26.
//

import SwiftUI

struct ProviderLogoView: View {
    let provider: String
    var size: CGFloat = 24

    var body: some View {
        switch provider.lowercased() {
        case "onedrive":
            OneDriveLogoView(size: size)
        case "dropbox":
            DropboxLogoView(size: size)
        default:
            GoogleDriveLogoView(size: size)
        }
    }
}
