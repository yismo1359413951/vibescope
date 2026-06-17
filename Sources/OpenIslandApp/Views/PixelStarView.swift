import SwiftUI

/// 紫微折叠胶囊吉祥物：一颗紫色五角星（★），会轻轻闪烁（帝星感）。
struct PixelStarView: View {
    var size: CGFloat = 24
    var lively: Bool = true
    /// 马卡龙紫。
    var color: Color = Color(red: 0xC2 / 255.0, green: 0xAA / 255.0, blue: 0xEE / 255.0)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { context in
            let speed = lively ? 2.6 : 1.2
            let t = (sin(context.date.timeIntervalSinceReferenceDate * speed) + 1) / 2
            FivePointStar()
                .fill(color)
                .overlay(
                    FivePointStar()
                        .fill(Color.white.opacity(0.25 + t * 0.25))
                        .scaleEffect(0.42)
                )
                .frame(width: size * 0.82, height: size * 0.82)
                .scaleEffect(0.92 + t * 0.12)
                .shadow(color: color.opacity(0.4 + t * 0.35), radius: 2 + t * 2.5)
                .frame(width: size, height: size)
        }
    }
}

/// 标准五角星路径（5 外角 + 5 内角），顶点朝上。
struct FivePointStar: Shape {
    var pointiness: CGFloat = 0.42  // 内/外半径比

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * pointiness
        var path = Path()
        for i in 0..<10 {
            let radius = i.isMultiple(of: 2) ? outer : inner
            // 从正上方开始（-90°），每 36° 一个顶点。
            let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
