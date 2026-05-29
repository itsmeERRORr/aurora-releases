import SwiftUI

struct StorageView: View {
    @Bindable var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topbar
                summaryCard
                volumesPanel
                eventFoldersPanel
            }
            .padding(.horizontal, AuroraSpacing.mainPaddingH)
            .padding(.vertical, AuroraSpacing.mainPaddingV)
        }
        .scrollIndicators(.hidden)
    }

    private var topbar: some View {
        HStack(spacing: 14) {
            IconChip(systemName: "externaldrive.fill", color: .auroraViolet, size: 36, iconScale: 0.5)
            Text("Storage")
                .font(.auroraTopbarH2)
                .tracking(-0.4)
                .foregroundStyle(Color.auroraTxt)
            Spacer()
        }
        .padding(.bottom, 6)
    }

    // MARK: - Summary

    private var summaryCard: some View {
        let summary = computeSummary()
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Destination")
                    .font(.manrope(10.5, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.auroraFaint)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline) {
                Text(summary.usedValue)
                    .font(.sora(36, weight: .heavy))
                    .foregroundStyle(Color.auroraTxt)
                Text(summary.usedUnit)
                    .font(.sora(18, weight: .semibold))
                    .foregroundStyle(Color.auroraMuted)
                Spacer()
                Text("\(Int((summary.fraction * 100).rounded()))%")
                    .font(.sora(15, weight: .bold))
                    .foregroundStyle(Color.auroraMuted)
            }
            StorageBar(fraction: summary.fraction, height: 8, radius: 4)
            Text(summary.subtitle)
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .auroraStaticCard(radius: AuroraRadius.large, paddingH: 22, paddingV: 22)
    }

    private struct Summary {
        let usedValue: String
        let usedUnit: String
        let fraction: Double
        let subtitle: String
    }

    private func computeSummary() -> Summary {
        let used = appState.totalStatsReport?.totalBytes ?? 0
        let usedParts = AuroraFormat.bytesParts(used)
        if let dest = appState.destinationURL,
           let values = try? dest.resourceValues(forKeys: [.volumeTotalCapacityKey]),
           let capacity = values.volumeTotalCapacity, capacity > 0 {
            let totalParts = AuroraFormat.bytesParts(Int64(capacity))
            return Summary(
                usedValue: usedParts.value,
                usedUnit: usedParts.unit,
                fraction: min(1, Double(used) / Double(capacity)),
                subtitle: "of \(totalParts.value) \(totalParts.unit) on \(dest.lastPathComponent)"
            )
        }
        return Summary(usedValue: usedParts.value, usedUnit: usedParts.unit,
                       fraction: 0, subtitle: "Destination not set")
    }

    // MARK: - Volumes

    @ViewBuilder
    private var volumesPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Mounted Volumes")

            if appState.mountedVolumes.isEmpty {
                empty(message: "No external volumes mounted")
            } else {
                VStack(spacing: 4) {
                    ForEach(appState.mountedVolumes) { volume in
                        volumeRow(volume)
                    }
                }
            }
        }
        .auroraStaticCard()
    }

    private func volumeRow(_ vol: VolumeInfo) -> some View {
        HStack(spacing: 12) {
            IconChip(systemName: vol.isActive ? "sdcard.fill" : "externaldrive", color: vol.isActive ? .auroraCyan : .auroraMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text(vol.name)
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                Text(vol.path.path)
                    .font(.manrope(11, weight: .medium))
                    .foregroundStyle(Color.auroraFaint)
                    .lineLimit(1)
            }
            Spacer()
            if vol.rawFileCount > 0 {
                Text("\(AuroraFormat.count(vol.rawFileCount)) RAW")
                    .font(.sora(11.5, weight: .bold))
                    .foregroundStyle(Color.auroraCyan)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.auroraCyan.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(Color.auroraCyan.opacity(0.25), lineWidth: 1))
            }
        }
        .padding(8)
    }

    // MARK: - Event folders

    @ViewBuilder
    private var eventFoldersPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Event Folders")
            let dests = appState.uniqueImportDestinations
            if dests.isEmpty {
                empty(message: "No event folders configured")
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(dests.enumerated()), id: \.offset) { _, dest in
                        eventRow(name: dest.name, path: dest.path)
                    }
                }
            }
        }
        .auroraStaticCard()
    }

    private func eventRow(name: String, path: String) -> some View {
        let agg = appState.importStats(forEventPath: path)
        return HStack(spacing: 12) {
            IconChip(systemName: "folder.fill", color: .auroraViolet)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                Text(path.isEmpty ? "Path unavailable" : path)
                    .font(.manrope(11, weight: .medium))
                    .foregroundStyle(Color.auroraFaint)
                    .lineLimit(1)
            }
            Spacer()
            if let agg = agg {
                let parts = AuroraFormat.bytesParts(agg.totalBytes)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(parts.value) \(parts.unit)")
                        .font(.sora(13, weight: .bold))
                        .foregroundStyle(Color.auroraTxt)
                    Text("\(AuroraFormat.count(agg.photoCount)) photos")
                        .font(.manrope(11, weight: .semibold))
                        .foregroundStyle(Color.auroraFaint)
                }
            }
        }
        .padding(8)
    }

    private func empty(message: String) -> some View {
        Text(message)
            .font(.manrope(12, weight: .semibold))
            .foregroundStyle(Color.auroraFaint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }
}
