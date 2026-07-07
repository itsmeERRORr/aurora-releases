import SwiftUI

enum LensDisplayFormatter {
    static func displayName(make: String, model: String) -> String {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = model.uppercased()

        if upper.contains("15MM F1.4"), upper.contains("FISHEYE") {
            return "15mm F1.4 FISHEYE"
        }
        if upper.contains("10MM F2.8") {
            return "10mm F2.8"
        }

        var result = model
            .replacingOccurrences(of: "Sony ", with: "")
            .replacingOccurrences(of: "SONY ", with: "")
            .replacingOccurrences(of: "FE ", with: "")
            .replacingOccurrences(of: "DT ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip any remaining brand prefix (e.g. "SAMYANG AF 85mm" → "AF 85mm")
        let upperResult = result.uppercased()
        let upperMake = make.uppercased().trimmingCharacters(in: .whitespaces)
        if !upperMake.isEmpty, upperResult.hasPrefix(upperMake + " ") {
            result = String(result.dropFirst(upperMake.count + 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result
    }

    static func brandName(make: String, model: String) -> String {
        let upperModel = model.uppercased()
        let upperMake = make.uppercased()

        if upperModel.contains("LAOWA") { return "LAOWA" }
        if upperModel.contains("SIGMA") || upperModel.contains("DG DN") || upperModel.contains("| ART") || upperModel.contains("FISHEYE") { return "SIGMA" }
        if upperModel.contains("SAMYANG") { return "SAMYANG" }
        if upperModel.contains("TAMRON") { return "TAMRON" }
        if upperMake.contains("RICOH") { return "RICOH" }
        if upperMake.contains("SONY") { return "SONY" }

        return make.isEmpty ? "LENS" : make.uppercased()
    }
}

struct TopLensesPanel: View {
    @Bindable var appState: AppState
    var report: StatsReport?
    var onViewAll: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let allLenses = report?.allLenses ?? []
            AuroraPanelHeader(title: "Top Lenses", actionLabel: allLenses.count > 5 ? "View all →" : nil, action: onViewAll)

            let lenses = allLenses.prefix(5)

            if lenses.isEmpty {
                emptyState
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(lenses), id: \.id) { lens in
                        TopLensRow(lens: lens)
                    }
                }
                .frame(minHeight: 266, alignment: .top)
            }
        }
        .auroraCollapsibleStaticCard(storageKey: "dashboard.topLenses")
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No lens data yet")
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
            Text("Lenses detected from EXIF appear here.")
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct TopLensRow: View {
    let lens: StatsReport.LensStat

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            RankBadge(rank: lens.rank)

            IconChip(systemName: "camera.aperture", color: accentForRank(lens.rank), size: 34, iconScale: 0.5)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.auroraEventName)
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(1)
                Text(brandName)
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraFaint)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            SpeedPill(text: "\(AuroraFormat.count(lens.count))", tint: accentForRank(lens.rank))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(hovering ? Color.auroraPanel2 : Color.clear)
        )
        .onHover { hovering = $0 }
    }

    private var displayName: String {
        LensDisplayFormatter.displayName(make: lens.make, model: lens.model)
    }

    private var brandName: String {
        LensDisplayFormatter.brandName(make: lens.make, model: lens.model)
    }

    private func accentForRank(_ rank: Int) -> Color {
        switch rank {
        case 1: return .auroraCyan
        case 2: return .auroraViolet
        case 3: return .auroraMagenta
        default: return .auroraBlue
        }
    }
}
