//
//  OneDriveLogoView.swift
//  Horizon
//
//  Created by Horizon on 29/10/26.
//

import SwiftUI
import AppKit

struct OneDriveLogoView: View {
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let _ = NSImage(named: "OneDriveLogo") {
                Image("OneDriveLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "cloud.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Color(red: 0.0, green: 0.47, blue: 0.83))
            }
        }
        .frame(width: size, height: size)
    }
}
