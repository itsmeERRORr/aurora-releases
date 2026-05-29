import SwiftUI

/// Shows the first photo in an event folder when accessible, otherwise the
/// Aurora signature gradient for the event.
struct EventThumbnail: View {
    let eventName: String
    /// Optional folder path — when present, a QL thumbnail is requested.
    var folderPath: String? = nil
    var cornerRadius: CGFloat = 8
    var overlay: AnyView? = nil

    @StateObject private var loader = EventThumbnailLoader.shared

    var body: some View {
        ZStack {
            EventGradients.gradient(for: eventName)
                .overlay(
                    // Subtle radial highlight from the handoff
                    RadialGradient(
                        colors: [Color.white.opacity(0.16), .clear],
                        center: UnitPoint(x: 0.38, y: 0.22),
                        startRadius: 0, endRadius: 180
                    )
                )

            if let path = folderPath, let img = loader.image(forFolderPath: path) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }

            overlay
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear {
            if let path = folderPath {
                loader.requestLoad(folderPath: path)
            }
        }
        .id(loader.version) // re-evaluate when cache changes
    }
}

#Preview {
    HStack(spacing: 8) {
        EventThumbnail(eventName: "R6 SLC Major 2026")
            .frame(width: 44, height: 34)
        EventThumbnail(eventName: "Six Invitational 2026")
            .frame(width: 44, height: 34)
        EventThumbnail(eventName: "Liga Portugal - Etapa 1", cornerRadius: 12)
            .frame(width: 180, height: 110)
    }
    .padding(40)
    .background(Color.auroraBg)
}
