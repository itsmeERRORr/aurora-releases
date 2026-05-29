import Foundation

enum NavigationItem: Equatable, Identifiable, Hashable {
    case dashboard
    case statistics
    case activity
    case storage
    case settings
    case logs
    case event(index: Int)

    var id: String {
        switch self {
        case .dashboard: return "dashboard"
        case .statistics: return "statistics"
        case .activity: return "activity"
        case .storage: return "storage"
        case .settings: return "settings"
        case .logs: return "logs"
        case .event(let idx): return "event-\(idx)"
        }
    }

    var label: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .statistics: return "Import Statistics"
        case .activity: return "Activity"
        case .storage: return "Storage"
        case .settings: return "Settings"
        case .logs: return "Logs"
        case .event: return ""
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .statistics: return "chart.bar.fill"
        case .activity: return "waveform.path.ecg"
        case .storage: return "externaldrive.fill"
        case .settings: return "gearshape.fill"
        case .logs: return "list.bullet.rectangle"
        case .event: return "folder.fill"
        }
    }
}
