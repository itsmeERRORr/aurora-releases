import SwiftUI

struct LineChartView: View {
    let data: [(label: String, count: Int)]

    @State private var animatedFractions: [CGFloat] = []
    @State private var showTrendLine = false
    @State private var hoveredIndex: Int? = nil

    private let barMaxHeight: CGFloat = 120
    private let barWidth: CGFloat = 22

    var body: some View {
        let chartData = data
        let maxCount = max(chartData.map { $0.count }.max() ?? 1, 1)

        GeometryReader { geo in
            let totalBars = max(chartData.count, 1)
            let availableWidth = geo.size.width
            // Space bars evenly; if few bars, use fixed spacing; if many, compress
            let computedSpacing = totalBars > 1
                ? max(4, (availableWidth - CGFloat(totalBars) * barWidth) / CGFloat(totalBars - 1))
                : 0

            ZStack(alignment: .bottom) {
                // Subtle grid lines
                VStack(spacing: 0) {
                    ForEach([0.75, 0.5, 0.25], id: \.self) { fraction in
                        Spacer()
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 1)
                    }
                    Spacer()
                }
                .frame(height: barMaxHeight)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 28) // leave room for labels

                // Dotted orange trend line — appears after bars finish growing
                if showTrendLine && chartData.count >= 2 {
                    ActivityTrendLineShape(
                        fractions: animatedFractions,
                        barWidth: barWidth,
                        spacing: computedSpacing,
                        maxHeight: barMaxHeight
                    )
                    .stroke(
                        Color.orange,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4])
                    )
                    .frame(height: barMaxHeight)
                    .padding(.bottom, 28)
                    .transition(.opacity)
                }

                // Bars + labels
                HStack(alignment: .bottom, spacing: computedSpacing) {
                    ForEach(chartData.indices, id: \.self) { index in
                        let item = chartData[index]
                        let fraction = index < animatedFractions.count ? animatedFractions[index] : 0
                        let isHovered = hoveredIndex == index

                        VStack(spacing: 5) {
                            // Tooltip: count on hover — fixedSize lets it overflow the bar width
                            Text("\(item.count)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.95))
                                .fixedSize()
                                .opacity(isHovered ? 1 : 0)
                                .animation(.easeInOut(duration: 0.12), value: isHovered)

                            // Capsule bar
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.28, green: 0.68, blue: 1.0),
                                            Color(red: 0.15, green: 0.45, blue: 0.90).opacity(0.72)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: barWidth, height: max(fraction * barMaxHeight, 5))
                                .shadow(
                                    color: Color(red: 0.28, green: 0.68, blue: 1.0)
                                        .opacity(isHovered ? 0.55 : 0.18),
                                    radius: 6, x: 0, y: 0
                                )
                                .scaleEffect(x: isHovered ? 1.15 : 1.0, anchor: .bottom)
                                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHovered)

                            // Label below bar
                            Text(shortLabel(item.label))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(isHovered ? .white : .textSecondary)
                                .lineLimit(1)
                                .animation(.easeInOut(duration: 0.12), value: isHovered)
                        }
                        .frame(width: barWidth)
                        .onHover { hovering in
                            hoveredIndex = hovering ? index : nil
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { startAnimation() }
        .onChange(of: data.count) { _, _ in startAnimation() }
    }

    // Shorten label: "Jan 2024" → "Jan", "2024-W01" → "W01", "2024" → "2024"
    private func shortLabel(_ label: String) -> String {
        if label.contains("-W") {
            // Week: "2024-W01" → "W01"
            return String(label.split(separator: "-").last ?? Substring(label))
        }
        // Month: take first 3 chars; year: leave as-is
        return String(label.prefix(3))
    }

    private func startAnimation() {
        let chartData = data
        let maxCount = max(chartData.map { $0.count }.max() ?? 1, 1)

        animatedFractions = Array(repeating: 0, count: chartData.count)
        showTrendLine = false

        for index in chartData.indices {
            let target = CGFloat(chartData[index].count) / CGFloat(maxCount)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72).delay(Double(index) * 0.035)) {
                animatedFractions[index] = target
            }
        }

        let totalDelay = 0.45 + Double(chartData.count) * 0.035 + 0.1
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(totalDelay))
            withAnimation(.easeIn(duration: 0.3)) {
                showTrendLine = true
            }
        }
    }
}

/// Polyline connecting the top-centre of each animated bar.
struct ActivityTrendLineShape: Shape {
    let fractions: [CGFloat]
    let barWidth: CGFloat
    let spacing: CGFloat
    let maxHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        guard fractions.count >= 2 else { return Path() }
        var path = Path()
        for (index, fraction) in fractions.enumerated() {
            let x = CGFloat(index) * (barWidth + spacing) + barWidth / 2
            let y = rect.height - max(fraction * maxHeight, 5)
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}
