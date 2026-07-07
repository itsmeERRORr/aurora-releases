import SwiftUI

/// A gentle pulsing-opacity loop, applied to skeleton placeholder blocks so a
/// "still loading" card reads as active rather than a fixed gray box.
private struct AuroraSkeletonPulse: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(pulsing ? 0.4 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

extension View {
    func auroraSkeletonPulse() -> some View {
        modifier(AuroraSkeletonPulse())
    }
}

private struct AuroraSkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.auroraStroke2)
            .frame(width: width, height: height)
    }
}

/// Mirrors `TopEventRow`/`LatestEventRow`'s layout (rank badge + thumbnail +
/// two text lines + trailing pill) so the loading state doesn't jump/reflow
/// once real rows replace it.
private struct AuroraSkeletonEventRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.auroraStroke2)
                .frame(width: 22, height: 22)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.auroraStroke2)
                .frame(width: 44, height: 34)
            VStack(alignment: .leading, spacing: 6) {
                AuroraSkeletonBlock(width: 130, height: 12)
                AuroraSkeletonBlock(width: 74, height: 9)
            }
            Spacer(minLength: 4)
            AuroraSkeletonBlock(width: 48, height: 20, cornerRadius: 10)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

/// Drop-in placeholder for "Top Events"/"Latest Events"-style row lists while
/// their first async load is still in flight (see the matching `hasLoadedOnce`
/// comment in TopEventsPanel.swift) — replaces a misleading "No events yet"
/// empty state that would otherwise flash before real data arrives.
struct AuroraSkeletonEventList: View {
    var rows: Int = 3

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<rows, id: \.self) { _ in
                AuroraSkeletonEventRow()
            }
        }
        .auroraSkeletonPulse()
    }
}

/// Placeholder for the "Most RAW/Deliverable Photos per Event" curve charts —
/// three bars of varying height standing in for the three plotted nodes.
struct AuroraSkeletonChart: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 28) {
            AuroraSkeletonBlock(width: 64, height: 96, cornerRadius: 10)
            AuroraSkeletonBlock(width: 64, height: 150, cornerRadius: 10)
            AuroraSkeletonBlock(width: 64, height: 70, cornerRadius: 10)
        }
        .frame(maxWidth: .infinity, minHeight: 232, alignment: .center)
        .auroraSkeletonPulse()
    }
}
