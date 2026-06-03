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

            grid

            Divider().background(Color.auroraStroke)

            actions
        }
        .padding(24)
        .frame(width: 520)
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
            row(icon: "doc", label: "Current file", value: appState.importProgress.currentFileName, mono: true)
            row(icon: "gauge.with.dots.needle.67percent", label: "Speed", value: appState.importProgress.speedFormatted, mono: true)
            row(icon: "clock", label: "Elapsed", value: appState.importProgress.elapsedFormatted, mono: true)
            row(icon: "arrow.down.circle", label: "Transferred", value: bytesFormatted, mono: true)
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
        default:
            return appState.importProgress.currentFileName.isEmpty
                ? "Working…"
                : appState.importProgress.currentFileName
        }
    }

    private var bytesFormatted: String {
        let transferred = Double(appState.importProgress.transferredBytes) / (1024 * 1024)
        let total = Double(appState.importProgress.totalBytes) / (1024 * 1024)
        return String(format: "%.0f / %.0f MB", transferred, total)
    }
}
