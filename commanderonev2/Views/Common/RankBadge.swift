import SwiftUI

/// Rank badge used in Top Events list (gold/silver/bronze/grey for 1/2/3/4+)
/// and in the Photos-per-Event chart nodes.
struct RankBadge: View {
    let rank: Int
    var size: CGFloat = 23
    var darkText: Bool { rank <= 3 }

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(
                Text("\(rank)")
                    .font(.sora(size * 0.46, weight: .heavy))
                    .foregroundStyle(darkText ? Color.auroraBg : Color.auroraMuted)
            )
    }

    private var fill: AnyShapeStyle {
        switch rank {
        case 1: return AnyShapeStyle(LinearGradient.auroraGold)
        case 2: return AnyShapeStyle(LinearGradient.auroraSilver)
        case 3: return AnyShapeStyle(LinearGradient.auroraBronze)
        default: return AnyShapeStyle(Color.white.opacity(0.1))
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        RankBadge(rank: 1)
        RankBadge(rank: 2)
        RankBadge(rank: 3)
        RankBadge(rank: 4)
    }
    .padding(40)
    .background(Color.auroraBg)
}
