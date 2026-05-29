import SwiftUI

struct FeaturedEventsPanel: View {
    @Bindable var appState: AppState
    var onSelect: (EventAggregate) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Featured Events")

            let aggregates = EventAggregator.build(appState: appState)
                .sorted { $0.totalFiles > $1.totalFiles }
            let featured = Array(aggregates.dropFirst(4).prefix(4))
            let display: [EventAggregate] = featured.isEmpty
                ? Array(aggregates.prefix(4))
                : featured

            if display.isEmpty {
                emptyState
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                    ],
                    spacing: 8
                ) {
                    ForEach(display) { event in
                        FeaturedCard(event: event) { onSelect(event) }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .auroraStaticCard()
    }

    private var emptyState: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
            spacing: 8
        ) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                    .fill(Color.auroraPanel2)
                    .aspectRatio(16.0/10.0, contentMode: .fit)
                    .overlay(
                        Text("No event")
                            .font(.manrope(11, weight: .semibold))
                            .foregroundStyle(Color.auroraFaint)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                            .strokeBorder(Color.auroraStroke, lineWidth: 1)
                    )
            }
        }
    }
}

struct FeaturedCard: View {
    let event: EventAggregate
    var onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            EventThumbnail(
                eventName: event.name,
                folderPath: event.id,
                cornerRadius: AuroraRadius.small,
                overlay: AnyView(
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.8)],
                            startPoint: .top, endPoint: .bottom
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.name)
                                .font(.manrope(12, weight: .bold))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                            Text("\(AuroraFormat.count(event.totalFiles)) RAW files")
                                .font(.manrope(10.5, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.72))
                        }
                        .padding(10)
                    }
                )
            )
            .aspectRatio(16.0/10.0, contentMode: .fit)
            .offset(y: hovering ? -2 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                    .strokeBorder(hovering ? Color.auroraStroke2 : Color.auroraStroke, lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.18), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
