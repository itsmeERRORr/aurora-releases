import SwiftUI

/// Multi-select chip picker for assigning `EventTag`s to an event/folder.
/// Used both inside EventStatsView and from the sidebar's "Edit Tags…" context menu.
struct EventTagPickerView: View {
    @Binding var selectedTags: Set<EventTag>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tags")
                .font(.manrope(13, weight: .bold))
                .foregroundStyle(Color.auroraTxt)

            FlowLayout(spacing: 6) {
                ForEach(EventTag.allCases) { tag in
                    tagChip(tag)
                }
            }
        }
        .padding(16)
        .frame(width: 252)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .fill(Color.auroraBg2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .strokeBorder(Color.auroraStroke2, lineWidth: 1)
        )
    }

    private func tagChip(_ tag: EventTag) -> some View {
        let isSelected = selectedTags.contains(tag)
        return Button {
            if isSelected {
                selectedTags.remove(tag)
            } else {
                selectedTags.insert(tag)
            }
        } label: {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                }
                Text(tag.rawValue)
                    .font(.manrope(11.5, weight: .semibold))
            }
            .foregroundStyle(isSelected ? tag.tint : Color.auroraMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tag.tint.opacity(isSelected ? 0.16 : 0.05))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tag.tint.opacity(isSelected ? 0.5 : 0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Single-select variant of the same chip grid — used by Compare, where each side
/// picks exactly one tag (and can't pick whatever the other side already has).
struct EventTagSinglePickerView: View {
    @Binding var selectedTag: EventTag?
    var excluding: EventTag?
    var onSelect: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tags")
                .font(.manrope(13, weight: .bold))
                .foregroundStyle(Color.auroraTxt)

            FlowLayout(spacing: 6) {
                ForEach(EventTag.allCases.filter { $0 != excluding }) { tag in
                    tagChip(tag)
                }
            }
        }
        .padding(16)
        .frame(width: 252)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .fill(Color.auroraBg2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .strokeBorder(Color.auroraStroke2, lineWidth: 1)
        )
    }

    private func tagChip(_ tag: EventTag) -> some View {
        let isSelected = selectedTag == tag
        return Button {
            selectedTag = isSelected ? nil : tag
            if !isSelected { onSelect?() }
        } label: {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                }
                Text(tag.rawValue)
                    .font(.manrope(11.5, weight: .semibold))
            }
            .foregroundStyle(isSelected ? tag.tint : Color.auroraMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tag.tint.opacity(isSelected ? 0.16 : 0.05))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tag.tint.opacity(isSelected ? 0.5 : 0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// "Edit tags"-style trigger button: tag icon + label, opens a popover picker on tap.
/// Used by the Compare tag pickers. Shows the tag icon only once a tag is actually
/// chosen — a placeholder like "Choose Tag A" has no icon.
struct EditTagButton: View {
    let label: String
    var tint: Color = .auroraMuted
    var hasSelection: Bool = false
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 6) {
                if hasSelection {
                    Image(systemName: "tag")
                        .font(.system(size: 10.5, weight: .bold))
                }
                Text(label)
                    .font(.manrope(12.5, weight: .semibold))
            }
            .foregroundStyle(hasSelection ? tint : Color.auroraMuted)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                    .fill(Color.auroraPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                    .strokeBorder(Color.auroraStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Simple wrapping HStack — items flow to the next line when they don't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Small read-only chip row, used to display an event's current tags.
struct EventTagChipsRow: View {
    let tags: Set<EventTag>

    var body: some View {
        if !tags.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(EventTag.allCases.filter { tags.contains($0) }) { tag in
                    Text(tag.rawValue)
                        .font(.manrope(11, weight: .semibold))
                        .foregroundStyle(tag.tint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(tag.tint.opacity(0.14))
                        )
                }
            }
        }
    }
}
