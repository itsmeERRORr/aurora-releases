import SwiftUI

struct HeroEventCard: View {
    @Bindable var appState: AppState
    var onViewEvent: () -> Void

    var body: some View {
        let info = resolveLatestEvent()

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leftPanel(info: info)
                    .frame(maxWidth: .infinity, alignment: .leading)
                rightPanel(info: info)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 320)
            }
            bottomStrip(info: info)
        }
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .fill(Color.auroraPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .strokeBorder(Color.auroraStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous))
    }

    // MARK: - Left

    private func leftPanel(info: LatestEventInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LATEST EVENT")
                .font(.manrope(10.5, weight: .bold))
                .tracking(1.9)
                .foregroundStyle(Color.auroraCyan)

            HStack(spacing: 8) {
                Text(info.name)
                    .font(.auroraHero)
                    .tracking(-0.8)
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(2)

                if info.isFinalized {
                    Text("Finalizado")
                        .font(.manrope(8.5, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.auroraFaint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.auroraPanel2))
                }
            }

            if let meta = info.meta {
                Text(meta)
                    .font(.manrope(13, weight: .semibold))
                    .foregroundStyle(Color.auroraMuted)
            }

            if let desc = info.description {
                Text(desc)
                    .font(.manrope(13, weight: .regular))
                    .foregroundStyle(Color.auroraFaint)
                    .lineSpacing(3)
                    .frame(maxWidth: 330, alignment: .leading)
            }

            Spacer(minLength: 4)

            if info.hasData {
                Button(action: onViewEvent) {
                    HStack(spacing: 6) {
                        Text("View Event")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                .buttonStyle(AuroraGradientButtonStyle())
            } else {
                Button {
                    // No-op; placeholder for "Connect a card" prompt.
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "externaldrive.badge.plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Connect a card to start")
                    }
                }
                .buttonStyle(AuroraGhostButtonStyle())
            }
        }
        .padding(.horizontal, AuroraSpacing.heroPaddingH)
        .padding(.vertical, AuroraSpacing.heroPaddingV)
    }

    // MARK: - Right

    private func rightPanel(info: LatestEventInfo) -> some View {
        ZStack {
            if info.hasData {
                EventThumbnail(
                    eventName: info.name,
                    folderPath: info.folderPath,
                    cornerRadius: 0,
                    overlay: AnyView(
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                glassBadge(info: info)
                                    .padding(14)
                            }
                        }
                    )
                )
            } else {
                HeroAuroraBackdrop()
            }
        }
    }

    private func glassBadge(info: LatestEventInfo) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.auroraLive)
                .frame(width: 7, height: 7)
                .shadow(color: Color.auroraLive.opacity(0.8), radius: 6)
            Text(info.badge)
                .font(.manrope(11.5, weight: .bold))
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.chip, style: .continuous)
                .fill(Color.auroraBg.opacity(0.6))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AuroraRadius.chip, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.chip, style: .continuous)
                .strokeBorder(Color.auroraStroke2, lineWidth: 1)
        )
    }

    // MARK: - Bottom strip

    private func bottomStrip(info: LatestEventInfo) -> some View {
        HStack(spacing: 0) {
            stripItem(icon: "photo.fill", value: info.strip.rawFiles, label: "RAW Files")
            stripDivider
            stripItem(icon: "externaldrive.fill", value: info.strip.data, label: "Data Imported")
            stripDivider
            stripItem(icon: "bolt.fill", value: info.strip.speed, label: "Avg Speed")
            stripDivider
            stripItem(icon: "calendar", value: info.strip.date, label: "Last Imported")
        }
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.018))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.auroraStroke),
            alignment: .top
        )
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(Color.auroraStroke)
            .frame(width: 1, height: 38)
    }

    private func stripItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 12) {
            IconChip(systemName: icon, color: .auroraViolet, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.sora(15, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                Text(label)
                    .font(.manrope(10.5, weight: .semibold))
                    .foregroundStyle(Color.auroraFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Data resolution

    private struct LatestEventInfo {
        let name: String
        let folderPath: String?
        let meta: String?
        let description: String?
        let badge: String
        let strip: HeroStrip
        let hasData: Bool
        let isFinalized: Bool
    }

    private struct HeroStrip {
        let rawFiles: String
        let data: String
        let speed: String
        let date: String
    }

    private func resolveLatestEvent() -> LatestEventInfo {
        guard let report = appState.lastImportReport else {
            return LatestEventInfo(
                name: "No imports yet",
                folderPath: nil,
                meta: nil,
                description: "Connect a card reader and import to see your most recent event here.",
                badge: "Idle",
                strip: HeroStrip(rawFiles: "—", data: "—", speed: "—", date: "—"),
                hasData: false,
                isFinalized: false
            )
        }

        let folderURL = URL(fileURLWithPath: report.destinationPath)
        let name = folderURL.lastPathComponent
        let date = report.timestamp

        // Aggregate matching history for richer description
        let agg = appState.importStats(forEventPath: report.destinationPath)
        let firstDate = agg?.firstDate ?? date
        let lastDate = agg?.lastDate ?? date

        let metaParts: [String] = [
            AuroraFormat.dateRange(firstDate, lastDate)
        ]
        let meta = metaParts.joined(separator: " · ")

        let sessions = agg?.sessionCount ?? 1
        let descTotal = agg?.photoCount ?? report.fileCount
        let description = "\(AuroraFormat.count(descTotal)) photos across \(sessions) import\(sessions == 1 ? "" : "s")."

        let bytes = AuroraFormat.bytesParts(report.totalBytes)
        let speed = AuroraFormat.speedParts(report.averageSpeed)

        let isFinalized = appState.finalizedEvent(matchingPath: report.destinationPath) != nil

        return LatestEventInfo(
            name: name,
            folderPath: report.destinationPath,
            meta: meta,
            description: description,
            badge: name.split(separator: " ").prefix(2).joined(separator: " "),
            strip: HeroStrip(
                rawFiles: AuroraFormat.count(report.fileCount),
                data: "\(bytes.value) \(bytes.unit)",
                speed: "\(speed.value) \(speed.unit)",
                date: AuroraFormat.dateCompact(lastDate)
            ),
            hasData: true,
            isFinalized: isFinalized
        )
    }
}
