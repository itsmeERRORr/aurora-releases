import SwiftUI

enum EventTag: String, CaseIterable, Identifiable, Codable {
    case corporate = "Corporate"
    case esports = "Esports"
    case family = "Family"
    case fashion = "Fashion"
    case liveEvents = "Live Events"
    case music = "Music"
    case nature = "Nature"
    case personal = "Personal"
    case sports = "Sports"
    case street = "Street"
    case studio = "Studio"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .corporate: return .auroraBlue
        case .esports: return .auroraCyan
        case .family: return .auroraBronze
        case .fashion: return .auroraAccent
        case .liveEvents: return .auroraLive
        case .music: return .auroraMagenta
        case .nature: return .auroraGold
        case .personal: return .auroraPurple
        case .sports: return .auroraHealthy
        case .street: return .auroraSilver
        case .studio: return .auroraViolet
        }
    }
}
