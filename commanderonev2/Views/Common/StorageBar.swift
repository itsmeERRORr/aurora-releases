import SwiftUI

/// Thin horizontal bar with gradient fill that animates from 0 → fraction on
/// appear. Used in the sidebar storage widget and in the per-month chart.
struct StorageBar: View {
    var fraction: Double
    var height: CGFloat = 6
    var radius: CGFloat = 4
    var trackColor: Color = .white.opacity(0.08)
    var fill: AnyShapeStyle = AnyShapeStyle(LinearGradient.auroraGrad)
    var animateOnAppear: Bool = true

    @State private var animatedFraction: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(trackColor)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
                    .frame(width: max(0, geo.size.width * CGFloat(animatedFraction)))
            }
        }
        .frame(height: height)
        .onAppear {
            if animateOnAppear {
                animatedFraction = 0
                withAnimation(.easeOut(duration: 1.1)) {
                    animatedFraction = max(0, min(1, fraction))
                }
            } else {
                animatedFraction = max(0, min(1, fraction))
            }
        }
        .onChange(of: fraction) { _, new in
            withAnimation(.easeOut(duration: 0.6)) {
                animatedFraction = max(0, min(1, new))
            }
        }
    }
}

#Preview {
    StorageBar(fraction: 0.61)
        .frame(width: 220)
        .padding(40)
        .background(Color.auroraBg)
}
