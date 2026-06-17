import SwiftUI

/// A deterministic pixel-art avatar (identicon / "space-invader" style) drawn
/// from a seed string. Same seed → same sprite + colour, so each session gets a
/// stable little creature. Mirrored horizontally for a symmetric look.
struct PixelAvatarView: View {
    let seed: String
    var size: CGFloat = 20
    /// When set, the avatar pulses gently (used to signal a running session).
    var pulsing: Bool = false

    private var hash: UInt64 {
        var h: UInt64 = 5381
        for byte in seed.utf8 {
            h = (h &* 33) ^ UInt64(byte)
        }
        return h
    }

    private var color: Color {
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.62, brightness: 0.96)
    }

    var body: some View {
        Group {
            if pulsing {
                TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { context in
                    let t = (sin(context.date.timeIntervalSinceReferenceDate * 3.0) + 1) / 2
                    sprite
                        .scaleEffect(1 + t * 0.08)
                        .shadow(color: color.opacity(0.35 + t * 0.25), radius: 3 + t * 2)
                }
            } else {
                sprite
            }
        }
        .frame(width: size, height: size)
    }

    private var sprite: some View {
        Canvas { ctx, canvasSize in
            let columns = 5
            let rows = 5
            let cell = min(canvasSize.width / CGFloat(columns), canvasSize.height / CGFloat(rows))
            let originX = (canvasSize.width - cell * CGFloat(columns)) / 2
            let originY = (canvasSize.height - cell * CGFloat(rows)) / 2
            let halfWidth = (columns + 1) / 2
            let h = hash

            for row in 0..<rows {
                for col in 0..<halfWidth {
                    let bitIndex = UInt64((row * halfWidth + col) % 63)
                    guard (h >> bitIndex) & 1 == 1 else { continue }
                    for mirroredCol in Set([col, columns - 1 - col]) {
                        let rect = CGRect(
                            x: originX + CGFloat(mirroredCol) * cell,
                            y: originY + CGFloat(row) * cell,
                            width: cell - 0.5,
                            height: cell - 0.5
                        )
                        ctx.fill(Path(roundedRect: rect, cornerRadius: cell * 0.18), with: .color(color))
                    }
                }
            }
        }
    }
}
