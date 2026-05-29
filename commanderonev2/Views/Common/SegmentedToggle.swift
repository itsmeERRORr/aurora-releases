import SwiftUI

/// Two-option pill toggle from the Aurora handoff
/// (`[Last Import] [Total]`). Generic over the selection type.
struct SegmentedToggle<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                }
                .buttonStyle(AuroraGhostButtonStyle(active: selection == option.value))
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                .fill(Color.auroraPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                .strokeBorder(Color.auroraStroke, lineWidth: 1)
        )
    }
}

enum StatsMode: Hashable {
    case lastImport
    case total
}

#Preview {
    @Previewable @State var mode: StatsMode = .lastImport
    return SegmentedToggle(
        options: [(.lastImport, "Last Import"), (.total, "Total")],
        selection: $mode
    )
    .padding(40)
    .background(Color.auroraBg)
}
