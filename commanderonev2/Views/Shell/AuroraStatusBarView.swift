import SwiftUI

struct AuroraStatusBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            leftStateItem
            divider
            queueItem
            divider
            lastImportItem
            Spacer(minLength: 12)
            healthItem
        }
        .frame(height: AuroraSpacing.statusBarHeight)
        .background(
            Color.auroraBg.opacity(0.7)
                .background(.ultraThinMaterial)
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.auroraStroke),
            alignment: .top
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.auroraStroke)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 14)
    }

    // MARK: - Items

    private var leftStateItem: some View {
        HStack(spacing: 9) {
            stateIcon
            Text(stateText)
                .font(.manrope(11.5, weight: .semibold))
                .foregroundStyle(Color.auroraMuted)
                .lineLimit(1)
        }
        .padding(.leading, 18)
    }

    private var queueItem: some View {
        HStack(spacing: 9) {
            Image(systemName: "list.bullet")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
            Text("Import queue: \(queueCount) item\(queueCount == 1 ? "" : "s")")
                .font(.manrope(11.5, weight: .semibold))
                .foregroundStyle(Color.auroraMuted)
        }
    }

    private var lastImportItem: some View {
        HStack(spacing: 9) {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
            Text(lastImportText)
                .font(.manrope(11.5, weight: .semibold))
                .foregroundStyle(Color.auroraMuted)
                .lineLimit(1)
        }
    }

    private var healthItem: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Color.auroraHealthy)
                .frame(width: 8, height: 8)
                .shadow(color: Color.auroraHealthy.opacity(0.8), radius: 6)
            Text("System healthy")
                .font(.manrope(11.5, weight: .semibold))
                .foregroundStyle(Color.auroraMuted)
        }
        .padding(.trailing, 18)
    }

    // MARK: - State

    @ViewBuilder
    private var stateIcon: some View {
        switch appState.importState {
        case .scanning, .importing, .verifying, .generatingStats:
            SpinnerRing(color: .auroraCyan)
                .frame(width: 14, height: 14)
        case .done, .ejectingDone:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.auroraHealthy)
        case .ejecting:
            Image(systemName: "eject.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.auroraGold)
        case .paused:
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.auroraGold)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.auroraLive)
        case .idle:
            if appState.activeVolume != nil {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.auroraCyan)
            } else {
                SpinnerRing(color: .auroraCyan)
                    .frame(width: 14, height: 14)
            }
        }
    }

    private var stateText: String {
        switch appState.importState {
        case .idle:
            if let vol = appState.activeVolume {
                return "Card detected: \(vol.name)"
            }
            return "Waiting for card reader…"
        case .scanning: return "Scanning files…"
        case .importing:
            return "Importing \(appState.importProgress.completedFiles)/\(appState.importProgress.totalFiles)…"
        case .paused: return "Import paused"
        case .verifying: return "Verifying…"
        case .done: return "Import complete"
        case .ejecting: return "Ejecting card…"
        case .ejectingDone: return "Ejecting card… Done"
        case .generatingStats: return "Generating stats…"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private var queueCount: Int {
        switch appState.importState {
        case .scanning, .importing, .verifying, .generatingStats: return 1
        default: return 0
        }
    }

    private var lastImportText: String {
        guard let report = appState.lastImportReport else {
            return "Last import: —"
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy 'at' HH:mm"
        return "Last import: \(f.string(from: report.timestamp))"
    }
}

/// Spinning ring used in the status bar when work is in flight.
struct SpinnerRing: View {
    var color: Color = .auroraCyan
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0.0, to: 0.7)
            .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    spinning = true
                }
            }
    }
}
