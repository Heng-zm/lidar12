import Foundation
import SwiftUI

struct DepthFieldArtwork: View {
    var palette: DepthPalette = .thermal

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                drawField(context: &context, size: size, time: time)
            }
        }
        .background {
            LinearGradient(
                colors: [
                    Color(hex: 0x071411).opacity(0.6),
                    Color(hex: 0x0A0D17).opacity(0.9),
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
        .allowsHitTesting(false)
    }

    private func drawField(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let cols = 21
        let rows = 18
        let stepX = size.width / CGFloat(cols + 2)
        let stepY = size.height / CGFloat(rows + 4)

        for row in 0...rows {
            for col in 0...cols {
                let u = CGFloat(col) / CGFloat(cols)
                let v = CGFloat(row) / CGFloat(rows)

                let waveA = sin(Double(u * 7.0) + time * 0.55) * 9
                let waveB = cos(Double(v * 6.0) - time * 0.38) * 7
                let depthWave = sin(Double(u * 4.2 + v * 3.4) + time * 0.32)

                let x = stepX * (CGFloat(col) + 1) + CGFloat(waveA) * (0.3 + v)
                let y = stepY * (CGFloat(row) + 2) + CGFloat(waveB) * 0.55

                let radial = sqrt(pow(Double(u - 0.58), 2) + pow(Double(v - 0.46), 2))
                let value = min(max(radial * 0.9 + depthWave * 0.10 + 0.24, 0), 1)
                let rgb = palette.color(at: Float(value))
                let color = Color(.sRGB, red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))

                let strength = 0.20 + (1.0 - v) * 0.62
                let diameter = 1.2 + (1.0 - v) * 1.8

                let rect = CGRect(
                    x: x - diameter / 2,
                    y: y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(strength)))
            }
        }

        let sweepProgress = CGFloat((time.truncatingRemainder(dividingBy: 6.5)) / 6.5)
        let sweepY = size.height * sweepProgress
        let sweepRect = CGRect(x: 0, y: sweepY - 38, width: size.width, height: 76)
        context.fill(
            Path(sweepRect),
            with: .linearGradient(
                Gradient(colors: [
                    AppTheme.accent.opacity(0),
                    AppTheme.accent.opacity(0.065),
                    AppTheme.cyan.opacity(0.11),
                    AppTheme.accent.opacity(0),
                ]),
                startPoint: CGPoint(x: 0, y: sweepRect.minY),
                endPoint: CGPoint(x: 0, y: sweepRect.maxY)
            )
        )

        var contour = Path()
        for ring in 0..<4 {
            let inset = CGFloat(28 + ring * 30)
            contour.addEllipse(in: CGRect(
                x: size.width * 0.72 - inset,
                y: size.height * 0.36 - inset * 0.72,
                width: inset * 2,
                height: inset * 1.44
            ))
        }
        context.stroke(contour, with: .color(AppTheme.accent.opacity(0.07)), lineWidth: 0.8)
    }
}
