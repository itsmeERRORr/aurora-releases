import SwiftUI

struct LatestImportsPanel: View {
    @Bindable var appState: AppState
    var onSelect: (ImportHistoryEntry) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Latest Event Imports", actionLabel: "View all →")

            let recent = Array(appState.importHistory
                .sorted(by: { $0.date > $1.date })
                .prefix(4))

            if recent.isEmpty {
                emptyState
            } else {
                VStack(spacing: 4) {
                    ForEach(recent) { entry in
                        LatestImportRow(entry: entry) { onSelect(entry) }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .auroraStaticCard()
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No imports yet")
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
            Text("Connect a card and import to see history here.")
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct LatestImportRow: View {
    let entry: ImportHistoryEntry
    var onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                EventThumbnail(eventName: entry.destinationName, folderPath: entry.destinationPath)
                    .frame(width: 44, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.destinationName)
                        .font(.auroraEventName)
                        .foregroundStyle(Color.auroraTxt)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(AuroraFormat.dateShort(entry.date))
                        Text("·").foregroundStyle(Color.auroraFaint)
                        Text(AuroraFormat.count(entry.fileCount))
                        Text("·").foregroundStyle(Color.auroraFaint)
                        let parts = AuroraFormat.bytesParts(entry.totalBytes)
                        Text("\(parts.value) \(parts.unit)")
                    }
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraFaint)
                }
                Spacer(minLength: 4)
                // Speed approximated from session — display only if non-zero.
                // ImportHistoryEntry does not carry duration, so omit when unknown.
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(hovering ? Color.auroraPanel2 : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
