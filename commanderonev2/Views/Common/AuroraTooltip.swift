import SwiftUI

struct AuroraTooltipModifier: ViewModifier {
    let text: String
    let edge: Edge
    @State private var isShowing = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                hoverTask?.cancel()
                if hovering {
                    hoverTask = Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        guard !Task.isCancelled else { return }
                        isShowing = true
                    }
                } else {
                    hoverTask = nil
                    isShowing = false
                }
            }
            .popover(isPresented: $isShowing, arrowEdge: edge) {
                Text(text)
                    .font(.manrope(12, weight: .medium))
                    .foregroundStyle(Color.auroraMuted)
                    .padding(12)
                    .frame(maxWidth: 240)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(Color.auroraPanel)
                    .environment(\.colorScheme, .dark)
            }
    }
}

extension View {
    @ViewBuilder
    func auroraTooltip(_ text: String, edge: Edge = .bottom) -> some View {
        if text.isEmpty {
            self
        } else {
            self.modifier(AuroraTooltipModifier(text: text, edge: edge))
        }
    }
}
