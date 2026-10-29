//
//  GoogleDriveLogoView.swift
//  Horizon
//
//  Created by Horizon on 29/10/26.
//

import SwiftUI
import AppKit

struct GoogleDriveLogoView: View {
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let _ = NSImage(named: "GoogleDriveLogo") {
                Image("GoogleDriveLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Canvas { context, canvasSize in
                    let rect = CGRect(origin: .zero, size: canvasSize)
                    let scaleX = rect.width / 512.0
                    let scaleY = rect.height / 512.0

                    // Path 1: Dark Blue corner
                    var p1 = Path()
                    p1.move(to: CGPoint(x: 38.7 * scaleX, y: 419.3 * scaleY))
                    p1.addLine(to: CGPoint(x: 61.3 * scaleX, y: 458.3 * scaleY))
                    p1.addLine(to: CGPoint(x: 161.3 * scaleX, y: 477.7 * scaleY))
                    p1.addLine(to: CGPoint(x: 161.3 * scaleX, y: 338.1 * scaleY))
                    p1.closeSubpath()
                    context.fill(p1, with: .color(Color(red: 0.0, green: 0.4, blue: 0.85)))

                    // Path 2: Green left diagonal
                    var p2 = Path()
                    p2.move(to: CGPoint(x: 256.0 * scaleX, y: 173.9 * scaleY))
                    p2.addLine(to: CGPoint(x: 175.4 * scaleX, y: 34.3 * scaleY))
                    p2.addLine(to: CGPoint(x: 7.0 * scaleX, y: 326.0 * scaleY))
                    p2.addLine(to: CGPoint(x: 161.3 * scaleX, y: 326.0 * scaleY))
                    p2.closeSubpath()
                    context.fill(p2, with: .color(Color(red: 0.0, green: 0.67, blue: 0.28)))

                    // Path 3: Red bottom corner
                    var p3 = Path()
                    p3.move(to: CGPoint(x: 431.4 * scaleX, y: 477.7 * scaleY))
                    p3.addLine(to: CGPoint(x: 504.7 * scaleX, y: 350.0 * scaleY))
                    p3.addLine(to: CGPoint(x: 350.7 * scaleX, y: 338.1 * scaleY))
                    p3.closeSubpath()
                    context.fill(p3, with: .color(Color(red: 0.92, green: 0.26, blue: 0.21)))

                    // Path 4: Blue bottom bar
                    var p4 = Path()
                    p4.move(to: CGPoint(x: 350.7 * scaleX, y: 338.1 * scaleY))
                    p4.addLine(to: CGPoint(x: 161.3 * scaleX, y: 338.1 * scaleY))
                    p4.addLine(to: CGPoint(x: 80.6 * scaleX, y: 477.7 * scaleY))
                    p4.addLine(to: CGPoint(x: 398.0 * scaleX, y: 477.7 * scaleY))
                    p4.closeSubpath()
                    context.fill(p4, with: .color(Color(red: 0.15, green: 0.52, blue: 0.99)))

                    // Path 5: Yellow right diagonal
                    var p5 = Path()
                    p5.move(to: CGPoint(x: 430.5 * scaleX, y: 182.7 * scaleY))
                    p5.addLine(to: CGPoint(x: 356.0 * scaleX, y: 53.7 * scaleY))
                    p5.addLine(to: CGPoint(x: 256.0 * scaleX, y: 173.9 * scaleY))
                    p5.addLine(to: CGPoint(x: 350.7 * scaleX, y: 338.1 * scaleY))
                    p5.closeSubpath()
                    context.fill(p5, with: .color(Color(red: 1.0, green: 0.73, blue: 0.0)))
                }
            }
        }
        .frame(width: size, height: size)
    }
}
