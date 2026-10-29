//
//  DropboxLogoView.swift
//  Horizon
//
//  Created by Horizon on 29/10/26.
//

import SwiftUI
import AppKit

struct DropboxLogoView: View {
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let _ = NSImage(named: "DropboxLogo") {
                Image("DropboxLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Canvas { context, canvasSize in
                    let rect = CGRect(origin: .zero, size: canvasSize)
                    let scaleX = rect.width / 512.0
                    let scaleY = rect.height / 512.0

                    let fill = Color(red: 0.0, green: 0.38, blue: 1.0) // Dropbox blue #0061FF

                    // Diamond 1 (Top Left)
                    var p1 = Path()
                    p1.move(to: CGPoint(x: 128 * scaleX, y: 64 * scaleY))
                    p1.addLine(to: CGPoint(x: 256 * scaleX, y: 149.3 * scaleY))
                    p1.addLine(to: CGPoint(x: 128 * scaleX, y: 234.7 * scaleY))
                    p1.addLine(to: CGPoint(x: 0 * scaleX, y: 149.3 * scaleY))
                    p1.closeSubpath()
                    context.fill(p1, with: .color(fill))

                    // Diamond 2 (Top Right)
                    var p2 = Path()
                    p2.move(to: CGPoint(x: 384 * scaleX, y: 64 * scaleY))
                    p2.addLine(to: CGPoint(x: 512 * scaleX, y: 149.3 * scaleY))
                    p2.addLine(to: CGPoint(x: 384 * scaleX, y: 234.7 * scaleY))
                    p2.addLine(to: CGPoint(x: 256 * scaleX, y: 149.3 * scaleY))
                    p2.closeSubpath()
                    context.fill(p2, with: .color(fill))

                    // Diamond 3 (Mid Left)
                    var p3 = Path()
                    p3.move(to: CGPoint(x: 0 * scaleX, y: 320 * scaleY))
                    p3.addLine(to: CGPoint(x: 128 * scaleX, y: 234.7 * scaleY))
                    p3.addLine(to: CGPoint(x: 256 * scaleX, y: 320 * scaleY))
                    p3.addLine(to: CGPoint(x: 128 * scaleX, y: 405.3 * scaleY))
                    p3.closeSubpath()
                    context.fill(p3, with: .color(fill))

                    // Diamond 4 (Mid Right)
                    var p4 = Path()
                    p4.move(to: CGPoint(x: 512 * scaleX, y: 320 * scaleY))
                    p4.addLine(to: CGPoint(x: 384 * scaleX, y: 234.7 * scaleY))
                    p4.addLine(to: CGPoint(x: 256 * scaleX, y: 320 * scaleY))
                    p4.addLine(to: CGPoint(x: 384 * scaleX, y: 405.3 * scaleY))
                    p4.closeSubpath()
                    context.fill(p4, with: .color(fill))

                    // Bottom flap
                    var p5 = Path()
                    p5.move(to: CGPoint(x: 256 * scaleX, y: 341.3 * scaleY))
                    p5.addLine(to: CGPoint(x: 384 * scaleX, y: 426.7 * scaleY))
                    p5.addLine(to: CGPoint(x: 256 * scaleX, y: 512 * scaleY))
                    p5.addLine(to: CGPoint(x: 128 * scaleX, y: 426.7 * scaleY))
                    p5.closeSubpath()
                    context.fill(p5, with: .color(fill))
                }
            }
        }
        .frame(width: size, height: size)
    }
}
