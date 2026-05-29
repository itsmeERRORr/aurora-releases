import SwiftUI

enum NavigationItem: Equatable, Identifiable {
    case dashboard
    case statistics
    case logs
    case event(index: Int)

    var id: String {
        switch self {
        case .dashboard: return "dashboard"
        case .statistics: return "statistics"
        case .logs: return "logs"
        case .event(let idx): return "event-\(idx)"
        }
    }

    var label: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .statistics: return "Import Statistics"
        case .logs: return "Logs"
        case .event: return "" // Event label comes from folder name
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .statistics: return "chart.bar.fill"
        case .logs: return "list.bullet.rectangle"
        case .event: return "folder.fill"
        }
    }
}

struct SidebarView: View {
    @Binding var selectedItem: NavigationItem
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo/Header
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        LinearGradient(colors: [Color.importCyan, Color.importPink], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .shadow(color: Color.importPink.opacity(0.35), radius: 18, x: 0, y: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("João's Photos")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("Import Manager")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 28)

            // Main Menu section
            VStack(alignment: .leading, spacing: 8) {
                Text("Main Menu")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(3)
                    .foregroundColor(.textSecondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 10)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 4) {
                    NavigationButton(
                        item: .dashboard,
                        label: "Dashboard",
                        isSelected: selectedItem == .dashboard
                    ) {
                        withAnimation(.smooth(duration: 0.3)) { selectedItem = .dashboard }
                    }
                    NavigationButton(
                        item: .statistics,
                        label: "Import Statistics",
                        isSelected: selectedItem == .statistics
                    ) {
                        withAnimation(.smooth(duration: 0.3)) { selectedItem = .statistics }
                    }

                    SidebarStaticRow(icon: "waveform.path.ecg", label: "Activity")
                }
            }
            .padding(.horizontal, 12)

            // Events section (from Import History destinations)
            if !appState.uniqueImportDestinations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Events")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(3)
                        .foregroundColor(.textSecondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 10)
                        .padding(.top, 22)

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 5) {
                            let destinations = appState.uniqueImportDestinations
                            ForEach(destinations.indices, id: \.self) { index in
                                NavigationButton(
                                    item: .event(index: index),
                                    label: destinations[index].name,
                                    isSelected: selectedItem == .event(index: index)
                                ) {
                                    withAnimation(.smooth(duration: 0.3)) { selectedItem = .event(index: index) }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
                .padding(.horizontal, 12)
            }

            Spacer(minLength: 16)

            storageSummaryCard
                .padding(.horizontal, 12)
                .padding(.bottom, 14)

            Rectangle()
                .fill(Color.importBorder.opacity(0.55))
                .frame(height: 1)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            // Logs at bottom
            VStack(alignment: .leading, spacing: 4) {
                NavigationButton(
                    item: .logs,
                    label: "Logs",
                    isSelected: selectedItem == .logs
                ) {
                    withAnimation(.smooth(duration: 0.3)) { selectedItem = .logs }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
        .frame(width: 250)
        .background(
            LinearGradient(
                colors: [Color(hex: "12283A"), Color(hex: "0B1020"), Color(hex: "080813")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(Rectangle().fill(Color.importBorder).frame(width: 1), alignment: .trailing)
    }

    private var storageSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textSecondary)
                Text("STORAGE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(3)
                    .foregroundColor(.textSecondary)
            }

            Text(formatBytes(totalBytes))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)

            Text("cached library")
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: [Color.importCyan, Color.importPink], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(proxy.size.width * storageProgress, 8))
                }
            }
            .frame(height: 6)

            HStack {
                Spacer()
                Text("\(Int(storageProgress * 100))%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.importBorder.opacity(0.8), lineWidth: 1))
    }

    private var totalBytes: Int64 {
        let statsBytes = appState.totalStatsReport?.totalBytes ?? 0
        return statsBytes > 0 ? statsBytes : appState.importHistory.reduce(Int64(0)) { $0 + $1.totalBytes }
    }

    private var storageProgress: CGFloat {
        let assumedCapacity: Double = 128 * 1024 * 1024 * 1024 * 1024
        guard totalBytes > 0 else { return 0.08 }
        return min(max(CGFloat(Double(totalBytes) / assumedCapacity), 0.08), 1)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let tb = Double(bytes) / (1024.0 * 1024.0 * 1024.0 * 1024.0)
        if tb >= 1 { return String(format: "%.1f TB", tb) }
        let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / (1024.0 * 1024.0))
    }
}

private struct SidebarStaticRow: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.textSecondary)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(0.9)
    }
}

struct NavigationButton: View {
    let item: NavigationItem
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isSelected ? .white : .textSecondary)
                    .frame(width: 20)

                Text(label)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : .textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected
                            ? LinearGradient(colors: [Color.importPurple.opacity(0.55), Color.importBlue.opacity(0.22)], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color.clear, Color.clear], startPoint: .leading, endPoint: .trailing)
                    )
                    .shadow(color: isSelected ? Color.importPurple.opacity(0.35) : .clear, radius: 14, x: 0, y: 6)
                    .animation(.smooth(duration: 0.3), value: isSelected)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.importPurple.opacity(0.9) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
