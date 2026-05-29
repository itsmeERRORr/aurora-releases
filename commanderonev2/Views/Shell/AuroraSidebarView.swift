import SwiftUI
import AppKit

struct AuroraSidebarView: View {
    @Binding var selectedItem: NavigationItem
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 18)

            sectionLabel("Main Menu")
                .padding(.horizontal, 18)
                .padding(.bottom, 6)

            VStack(spacing: 2) {
                navRow(.dashboard)
                navRow(.statistics)
                navRow(.activity)
                navRow(.storage)
                navRow(.settings)
            }
            .padding(.horizontal, 10)

            sectionLabel("Events")
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 6)

            eventsList
                .frame(maxHeight: .infinity)
                .layoutPriority(0)
                .padding(.bottom, 10)

            Divider()
                .background(Color.auroraStroke)
                .padding(.horizontal, 10)

            VStack(spacing: 2) {
                navRow(.logs)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .frame(width: AuroraSpacing.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            Color.auroraBg2
                .overlay(
                    Color.white.opacity(0.02) // soft glass
                )
        )
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundStyle(Color.auroraStroke),
            alignment: .trailing
        )
    }

    // MARK: - Brand

    private var brand: some View {
        HStack(spacing: 12) {
            GradientIconChip(systemName: "camera.aperture", size: 38)
            VStack(alignment: .leading, spacing: 0) {
                Text("João's Photos")
                    .font(.auroraBrand)
                    .foregroundStyle(Color.auroraTxt)
                Text("Import Manager")
                    .font(.manrope(11, weight: .medium))
                    .foregroundStyle(Color.auroraFaint)
            }
        }
    }

    // MARK: - Section label

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.auroraSectionLabel)
            .tracking(1.7)
            .foregroundStyle(Color.auroraFaint)
    }

    // MARK: - Nav row (main menu / logs)

    private func navRow(_ item: NavigationItem) -> some View {
        AuroraNavRow(
            label: item.label,
            systemIcon: item.icon,
            isActive: selectedItem == item
        ) {
            selectedItem = item
        }
    }

    // MARK: - Events list

    @ViewBuilder
    private var eventsList: some View {
        let events = appState.uniqueImportDestinations
        if events.isEmpty {
            Text("No events yet")
                .font(.manrope(12.5, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
                .italic()
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(events.enumerated()), id: \.offset) { idx, event in
                        eventRow(idx: idx, event: event)
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func eventRow(idx: Int, event: (path: String, name: String, bookmarkIndex: Int)) -> some View {
        let isFinalized = appState.finalizedEvent(forBookmarkIndex: event.bookmarkIndex) != nil

        HStack(spacing: 6) {
            AuroraNavRow(
                label: event.name,
                systemIcon: isFinalized ? "lock" : "folder",
                isActive: selectedItem == .event(index: idx),
                compact: true
            ) {
                selectedItem = .event(index: idx)
            }

            if isFinalized {
                Text("Finalizado")
                    .font(.manrope(8.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.auroraFaint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.auroraPanel2)
                    )
                    .padding(.trailing, 4)
            }
        }
        .contextMenu {
            if isFinalized {
                Button("Reopen Event…") {
                    confirmReopen(bookmarkIndex: event.bookmarkIndex, name: event.name)
                }
            } else {
                Button("Finalize Event…") {
                    confirmFinalize(bookmarkIndex: event.bookmarkIndex, name: event.name)
                }
            }
        }
    }

    private func confirmFinalize(bookmarkIndex: Int, name: String) {
        let alert = NSAlert()
        alert.messageText = "Finalize \(name)?"
        alert.informativeText = "Current totals will be saved permanently. New imports won't update them. You can reopen later."
        alert.addButton(withTitle: "Finalize")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if appState.finalizeEvent(at: bookmarkIndex) == nil {
            let warn = NSAlert()
            warn.messageText = "No fresh data for this folder"
            warn.informativeText = "Run a scan from the event detail view before finalizing."
            warn.addButton(withTitle: "OK")
            warn.runModal()
        }
    }

    private func confirmReopen(bookmarkIndex: Int, name: String) {
        let alert = NSAlert()
        alert.messageText = "Reopen \(name)?"
        alert.informativeText = "The snapshot will be deleted and the event will return to live counts. New imports will start counting again."
        alert.addButton(withTitle: "Reopen")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        appState.reopenEvent(at: bookmarkIndex)
    }

    // MARK: - Storage widget

    private var storageWidget: some View {
        let stats = computeStorage(appState: appState)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("STORAGE")
                    .font(.manrope(9.5, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.auroraFaint)
                Spacer()
                Text("\(Int((stats.fraction * 100).rounded()))%")
                    .font(.manrope(10.5, weight: .semibold))
                    .foregroundStyle(Color.auroraMuted)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(stats.usedValue)
                    .font(.sora(22, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                Text(stats.usedUnit)
                    .font(.sora(13, weight: .semibold))
                    .foregroundStyle(Color.auroraMuted)
            }

            StorageBar(fraction: stats.fraction)

            Text(stats.subtitle)
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
        }
    }

    private struct StorageSummary {
        let fraction: Double
        let usedValue: String
        let usedUnit: String
        let subtitle: String
    }

    private func computeStorage(appState: AppState) -> StorageSummary {
        let used = appState.totalStatsReport?.totalBytes ?? 0
        let usedParts = AuroraFormat.bytesParts(used)
        var totalBytes: Int64 = 0
        if let dest = appState.destinationURL,
           let values = try? dest.resourceValues(forKeys: [.volumeTotalCapacityKey]),
           let capacity = values.volumeTotalCapacity {
            totalBytes = Int64(capacity)
        }
        let fraction: Double = totalBytes > 0 ? Double(used) / Double(totalBytes) : 0
        let totalParts = totalBytes > 0
            ? AuroraFormat.bytesParts(totalBytes)
            : (value: "—", unit: "")
        let subtitle: String
        if totalBytes > 0 {
            subtitle = "of \(totalParts.value) \(totalParts.unit) used"
        } else if used > 0 {
            subtitle = "destination not set"
        } else {
            subtitle = "No imports yet"
        }
        return StorageSummary(
            fraction: fraction,
            usedValue: usedParts.value,
            usedUnit: usedParts.unit,
            subtitle: subtitle
        )
    }
}

// MARK: - Nav row component

struct AuroraNavRow: View {
    let label: String
    let systemIcon: String
    let isActive: Bool
    var compact: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: systemIcon)
                    .font(.system(size: compact ? 12 : 13.5, weight: .semibold))
                    .frame(width: 16)
                Text(label)
                    .font(.auroraNavItem)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, compact ? 7 : 9)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.badge, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.badge, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .shadow(color: isActive ? Color.auroraAccent.opacity(0.8) : .clear, radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.2), value: isActive)
    }

    private var textColor: Color {
        if isActive { return .white }
        if hovering { return .auroraTxt }
        return .auroraMuted
    }

    private var background: AnyShapeStyle {
        if isActive { return AnyShapeStyle(LinearGradient.auroraGradMuted) }
        if hovering { return AnyShapeStyle(Color.auroraPanel) }
        return AnyShapeStyle(Color.clear)
    }

    private var borderColor: Color {
        if isActive { return Color.auroraAccent.opacity(0.35) }
        return .clear
    }
}
