import SwiftUI

struct ProgressOverlayView: View {
    @Bindable var appState: AppState
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                IconChip(systemName: stateIcon, color: .auroraViolet, size: 36, iconScale: 0.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stateTitle)
                        .font(.sora(20, weight: .bold))
                        .foregroundStyle(Color.auroraTxt)
                    Text(stateSubtitle)
                        .font(.manrope(12, weight: .semibold))
                        .foregroundStyle(Color.auroraMuted)
                }
                Spacer()
            }

            progressBlock

            if appState.importJobs.count > 1 {
                multiJobList
            }

            if let importNotice {
                notice(importNotice)
            }

            grid

            Divider().background(Color.auroraStroke)

            actions
        }
        .padding(24)
        .frame(width: appState.importJobs.count > 1 ? 640 : 520)
        .background(
            // Solid opaque modal background so the card actually obscures the
            // app behind it. The default auroraStaticCard fill is
            // Color.white.opacity(0.035) — meant for in-page panels sitting
            // on top of the app background — and is effectively invisible
            // when used as a free-floating modal over a scrim.
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .fill(Color.auroraBg2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .strokeBorder(Color.auroraStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 16)
    }

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            StorageBar(
                fraction: appState.importProgress.fraction,
                height: 8, radius: 4,
                animateOnAppear: false
            )
            HStack {
                Text("\(appState.importProgress.completedFiles) / \(appState.importProgress.totalFiles) files")
                Spacer()
                Text("\(Int(appState.importProgress.fraction * 100))%")
            }
            .font(.manrope(11.5, weight: .semibold))
            .foregroundStyle(Color.auroraMuted)
        }
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
            row(icon: "doc", label: "Current file", value: currentFileDisplayName, mono: true)
            row(icon: "gauge.with.dots.needle.67percent", label: appState.importJobs.count > 1 ? "Total speed" : "Speed", value: appState.importProgress.speedFormatted, mono: true)
            row(icon: "clock", label: "Elapsed", value: appState.importProgress.elapsedFormatted, mono: true)
            row(icon: "arrow.down.circle", label: "Transferred", value: bytesFormatted, mono: true)
        }
    }

    private var multiJobList: some View {
        VStack(spacing: 10) {
            ForEach(appState.importJobs) { job in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: icon(for: job.state))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(color(for: job.state))
                        Text(job.sourceName)
                            .font(.manrope(12.5, weight: .bold))
                            .foregroundStyle(Color.auroraTxt)
                            .lineLimit(1)
                        Spacer()
                        Text(job.progress.speedFormatted)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.auroraCyan)
                    }

                    StorageBar(
                        fraction: job.progress.fraction,
                        height: 6,
                        radius: 3,
                        animateOnAppear: false
                    )

                    HStack(spacing: 8) {
                        Text("\(job.progress.completedFiles) / \(job.progress.totalFiles) files")
                        Text("•")
                            .foregroundStyle(Color.auroraFaint)
                        Text(jobLabel(for: job))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("\(Int(job.progress.fraction * 100))%")
                    }
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraMuted)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                        .fill(Color.auroraPanel2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                        .strokeBorder(Color.auroraStroke, lineWidth: 1)
                )
            }
        }
    }

    private func row(icon: String, label: String, value: String, mono: Bool) -> some View {
        GridRow {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
            }
            .foregroundStyle(Color.auroraMuted)
            .font(.manrope(12, weight: .semibold))

            Text(value)
                .font(mono ? .system(size: 12, weight: .semibold, design: .monospaced) : .manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraTxt)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func notice(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: appState.importProgress.failureMessage == nil ? "info.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(appState.importProgress.failureMessage == nil ? Color.auroraCyan : Color.auroraLive)
            Text(message)
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraTxt)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                .fill((appState.importProgress.failureMessage == nil ? Color.auroraCyan : Color.auroraLive).opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                .strokeBorder((appState.importProgress.failureMessage == nil ? Color.auroraCyan : Color.auroraLive).opacity(0.32), lineWidth: 1)
        )
    }

    private var actions: some View {
        HStack {
            Spacer()
            if appState.importState == .importing {
                Button("Pause", action: onPause).buttonStyle(AuroraGhostButtonStyle())
            } else if appState.importState == .paused {
                Button("Resume", action: onResume).buttonStyle(AuroraGradientButtonStyle(compact: true))
            }
            Button("Cancel", action: onCancel).buttonStyle(AuroraGhostButtonStyle())
        }
    }

    // MARK: - State

    private var stateIcon: String {
        switch appState.importState {
        case .scanning: return "magnifyingglass"
        case .importing: return "square.and.arrow.down"
        case .paused: return "pause.circle"
        case .verifying: return "checkmark.shield"
        case .done: return "checkmark.circle"
        case .error: return "exclamationmark.triangle.fill"
        case .ejecting, .ejectingDone: return "eject.fill"
        case .generatingStats: return "chart.bar.fill"
        default: return "square.and.arrow.down"
        }
    }

    private var stateTitle: String {
        switch appState.importState {
        case .scanning: return "Scanning…"
        case .importing: return "Importing…"
        case .paused: return "Paused"
        case .verifying: return "Verifying…"
        case .done: return "Import complete"
        case .error: return "Import failed"
        case .ejecting: return "Ejecting card…"
        case .ejectingDone: return "Ejecting card… Done"
        case .generatingStats: return "Generating stats…"
        default: return "Importing"
        }
    }

    private var stateSubtitle: String {
        switch appState.importState {
        case .importing:
            return "Don't disconnect the card or destination until this finishes."
        case .paused:
            return "Tap Resume to continue, Cancel to abort."
        case .done:
            return "Stats will refresh in a moment."
        case .error:
            return appState.importProgress.failureMessage ?? "Check the import details below."
        case .ejecting:
            return "Almost there…"
        case .ejectingDone:
            return "Card ejected safely."
        default:
            return appState.importProgress.currentFileName.isEmpty
                ? "Working…"
                : appState.importProgress.currentFileName
        }
    }

    private var currentFileDisplayName: String {
        switch appState.importState {
        case .ejecting:
            return "Almost there…"
        case .ejectingDone:
            return "Card ejected"
        default:
            return appState.importProgress.currentFileName
        }
    }

    private var bytesFormatted: String {
        let transferred = Double(appState.importProgress.transferredBytes) / (1024 * 1024)
        let total = Double(appState.importProgress.totalBytes) / (1024 * 1024)
        return String(format: "%.0f / %.0f MB", transferred, total)
    }

    private var importNotice: String? {
        appState.importProgress.failureMessage ?? appState.importProgress.statusMessage
    }

    private func jobLabel(for job: ImportJobProgress) -> String {
        switch job.state {
        case .scanning: return "Scanning"
        case .importing, .paused: return job.progress.currentFileName.isEmpty ? job.state.label : job.progress.currentFileName
        case .done: return "Import complete"
        case .ejecting: return "Ejecting"
        case .ejectingDone: return "Ejected"
        case .generatingStats: return "Generating stats"
        case .error(let message): return message
        default: return job.state.label
        }
    }

    private func icon(for state: ImportState) -> String {
        switch state {
        case .scanning: return "magnifyingglass"
        case .importing: return "square.and.arrow.down"
        case .paused: return "pause.circle"
        case .done: return "checkmark.circle.fill"
        case .ejecting, .ejectingDone: return "eject.fill"
        case .error: return "exclamationmark.triangle.fill"
        default: return "sdcard"
        }
    }

    private func color(for state: ImportState) -> Color {
        switch state {
        case .done, .ejectingDone: return .auroraHealthy
        case .error: return .auroraLive
        case .ejecting: return .auroraViolet
        default: return .auroraCyan
        }
    }
}
