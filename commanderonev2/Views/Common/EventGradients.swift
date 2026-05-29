import SwiftUI

/// Deterministic gradient palette used as fallback artwork for events when
/// no real thumbnail is available.
enum EventGradients {
    /// Stored gradients keyed by event name (from the handoff).
    private static let palette: [String: (Color, Color)] = [
        "R6 SLC Major 2026":         (Color(hex: "e23b5a"), Color(hex: "3b1d8e")),
        "Six Invitational 2026":     (Color(hex: "f59e0b"), Color(hex: "7c2d92")),
        "Liga Portugal - Etapa 1":   (Color(hex: "10b981"), Color(hex: "0a3d2e")),
        "eLiga Portugal - Etapa 1":  (Color(hex: "10b981"), Color(hex: "0a3d2e")),
        "eLiga Pro Series Final":    (Color(hex: "3b82f6"), Color(hex: "1e1b4b")),
        "Final Four - Liga 2026":    (Color(hex: "14b8a6"), Color(hex: "0f2942")),
        "Liga Portugal Premios":     (Color(hex: "d4a017"), Color(hex: "3a2d0a")),
        "eFADU 2026":                (Color(hex: "d946ef"), Color(hex: "4c1d95")),
        "Red Bull Run 2026":         (Color(hex: "fb923c"), Color(hex: "1e3a8a")),
        "Japan 2026":                (Color(hex: "f43f5e"), Color(hex: "3b1d6e")),
        "Taça eLiga 2026":           (Color(hex: "22d3ee"), Color(hex: "6d28d9")),
        "Red Bull Skate 2026":       (Color(hex: "84cc16"), Color(hex: "155e63")),
    ]

    /// Fallback palette cycled deterministically by hashing the event name.
    private static let cycle: [(Color, Color)] = [
        (Color(hex: "e23b5a"), Color(hex: "3b1d8e")),
        (Color(hex: "f59e0b"), Color(hex: "7c2d92")),
        (Color(hex: "10b981"), Color(hex: "0a3d2e")),
        (Color(hex: "3b82f6"), Color(hex: "1e1b4b")),
        (Color(hex: "14b8a6"), Color(hex: "0f2942")),
        (Color(hex: "d946ef"), Color(hex: "4c1d95")),
        (Color(hex: "fb923c"), Color(hex: "1e3a8a")),
        (Color(hex: "22d3ee"), Color(hex: "6d28d9")),
        (Color(hex: "84cc16"), Color(hex: "155e63")),
        (Color(hex: "f43f5e"), Color(hex: "3b1d6e")),
    ]

    static func colors(for eventName: String) -> (Color, Color) {
        if let p = palette[eventName] { return p }
        // Stable hash → cycle index
        let h = eventName.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return cycle[Int(h % UInt32(cycle.count))]
    }

    static func gradient(for eventName: String) -> LinearGradient {
        let (a, b) = colors(for: eventName)
        return LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The "stage light" gradient used for the hero event placeholder.
/// Layers three radial blobs + a base diagonal so the result feels like the
/// painted backdrop in the handoff (`evhero-img`).
struct HeroAuroraBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1a1340"), .auroraBg],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Ellipse()
                .fill(RadialGradient(colors: [.auroraMagenta.opacity(0.55), .clear],
                                     center: .center, startRadius: 0, endRadius: 200))
                .frame(width: 380, height: 380)
                .offset(x: -90, y: -40)
            Ellipse()
                .fill(RadialGradient(colors: [.auroraCyan.opacity(0.5), .clear],
                                     center: .center, startRadius: 0, endRadius: 220))
                .frame(width: 460, height: 420)
                .offset(x: 110, y: -60)
            Ellipse()
                .fill(RadialGradient(colors: [.auroraAccent.opacity(0.55), .clear],
                                     center: .center, startRadius: 0, endRadius: 240))
                .frame(width: 520, height: 480)
                .offset(x: 30, y: 140)
        }
        .compositingGroup()
    }
}
