import SwiftUI

/// Top header for grouped panels: section label on the left + optional "View
/// all →" link on the right.
struct AuroraPanelHeader: View {
    let title: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.auroraCardIsCollapsed) private var cardIsCollapsed

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            AuroraCollapsibleHeaderTitle(title: title)

            Spacer(minLength: 8)

            if let label = actionLabel, !cardIsCollapsed {
                Button(action: { action?() }) {
                    Text(label)
                        .font(.manrope(11.5, weight: .semibold))
                        .foregroundStyle(Color.auroraCyan)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 12)
    }
}
