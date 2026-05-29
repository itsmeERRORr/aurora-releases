import SwiftUI

/// Tiny SVG-style sparkline rendered via SwiftUI `Canvas` — line + area fill,
/// gradient stroke, smoothed using a Catmull-Rom-ish cubic curve.
struct Sparkline: View {
    var values: [Double]
    var stroke: [Color] = [.auroraCyan, .auroraCyanDeep]
    var fill: Color = .auroraCyan

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let points = makePoints(in: CGSize(width: w, height: h))

            Canvas { ctx, _ in
                guard points.count >= 2 else { return }

                // Build smoothed line path.
                let linePath = smoothPath(points: points)

                // Area fill: line + closure to baseline.
                var areaPath = linePath
                areaPath.addLine(to: CGPoint(x: points.last!.x, y: h))
                areaPath.addLine(to: CGPoint(x: points.first!.x, y: h))
                areaPath.closeSubpath()

                let areaShading = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [fill.opacity(0.32), .clear]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: h)
                )
                ctx.fill(areaPath, with: areaShading)

                let lineShading = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: stroke),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: w, y: 0)
                )
                ctx.stroke(linePath, with: lineShading, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func makePoints(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let range = max(maxV - minV, 0.0001)
        let stepX = values.count > 1 ? size.width / CGFloat(values.count - 1) : size.width
        return values.enumerated().map { i, v in
            let x = CGFloat(i) * stepX
            let normalized = (v - minV) / range
            let y = size.height - CGFloat(normalized) * (size.height - 2) - 1
            return CGPoint(x: x, y: y)
        }
    }

    /// Smoothed open path using approximate Catmull-Rom → cubic Bezier.
    private func smoothPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        let alpha: CGFloat = 0.5
        for i in 0..<(points.count - 1) {
            let p0 = i == 0 ? points[0] : points[i - 1]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : p2
            let c1 = CGPoint(
                x: p1.x + (p2.x - p0.x) * alpha / 3.0,
                y: p1.y + (p2.y - p0.y) * alpha / 3.0
            )
            let c2 = CGPoint(
                x: p2.x - (p3.x - p1.x) * alpha / 3.0,
                y: p2.y - (p3.y - p1.y) * alpha / 3.0
            )
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

#Preview {
    VStack(spacing: 20) {
        Sparkline(values: [3, 6, 4, 8, 7, 12, 9, 14, 11, 18])
            .frame(width: 160, height: 36)
        Sparkline(values: [12, 9, 14, 7, 11, 5, 8, 4, 9, 3],
                  stroke: [.auroraMagenta, .auroraMagentaDeep],
                  fill: .auroraMagenta)
            .frame(width: 160, height: 36)
    }
    .padding(40)
    .background(Color.auroraBg)
}
