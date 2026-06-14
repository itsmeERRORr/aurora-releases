import SwiftUI
import AppKit

struct RenameTemplateEditorSheet: View {
    @Bindable var appState: AppState
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    @State private var draftTemplate = ""
    @State private var imageNameToken = RenameTokenOption(label: "Filename", value: "{filename}")
    @State private var copyNameToken = RenameTokenOption(label: "Original filename", value: "{originalFilename}")
    @State private var sequenceToken = RenameTokenOption(label: "Sequence # (00001)", value: "{sequence:00001}")
    @State private var dateToken = RenameTokenOption(label: "Date (YYYYMMDD)", value: "{date:yyyyMMdd}")

    private var previewEventName: String {
        if let activeIndex = appState.activeEventFolderIndex,
           let name = appState.displayNameForEvent(at: activeIndex),
           !name.isEmpty {
            return name
        }
        return "FPF-Finals"
    }

    private var preview: String {
        RenameTemplateRenderer.preview(template: draftTemplate, eventName: previewEventName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Filename Template Editor")
                    .font(.sora(16, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(AuroraGhostButtonStyle())
                Button("Done") {
                    appState.renameTemplate = draftTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? RenameTemplateRenderer.defaultTemplate
                        : draftTemplate
                    onDone()
                    dismiss()
                }
                .buttonStyle(AuroraGradientButtonStyle(compact: true))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Example")
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(Color.auroraFaint)
                    .textCase(.uppercase)
                    .tracking(0.9)
                Text(preview)
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.auroraBg2, in: RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                            .strokeBorder(Color.auroraStroke2, lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Template")
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(Color.auroraFaint)
                    .textCase(.uppercase)
                    .tracking(0.9)
                RenameTemplateTextField(
                    text: $draftTemplate,
                    placeholder: "{date:yyyyMMdd}_{event}_{sequence:00001}_{filename}",
                    tokenValues: templateTokenValues
                )
                    .frame(height: 38)
                    .padding(10)
                    .background(Color.auroraBg2, in: RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                            .strokeBorder(Color.auroraCyan.opacity(0.55), lineWidth: 1)
                    )
            }

            tokenSection(title: "Image Name") {
                tokenInsertRow(selection: $imageNameToken, options: filenameOptions)
                tokenInsertRow(selection: $copyNameToken, options: copyNameOptions)
            }

            tokenSection(title: "Sequence and Date") {
                tokenInsertRow(selection: $sequenceToken, options: sequenceOptions)
                tokenInsertRow(selection: $dateToken, options: dateOptions)
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(Color.auroraBg)
        .onAppear {
            draftTemplate = appState.renameTemplate.isEmpty ? RenameTemplateRenderer.defaultTemplate : appState.renameTemplate
        }
    }

    private var filenameOptions: [RenameTokenOption] {
        [
            RenameTokenOption(label: "Filename", value: "{filename}"),
            RenameTokenOption(label: "Filename number suffix", value: "{filenameNumberSuffix}"),
            RenameTokenOption(label: "Folder Name", value: "{event}")
        ]
    }

    private var copyNameOptions: [RenameTokenOption] {
        [
            RenameTokenOption(label: "Original filename", value: "{originalFilename}"),
            RenameTokenOption(label: "Original number suffix", value: "{originalNumberSuffix}"),
            RenameTokenOption(label: "Copy name", value: "{copyName}")
        ]
    }

    private var sequenceOptions: [RenameTokenOption] {
        [
            RenameTokenOption(label: "Sequence # (1)", value: "{sequence}"),
            RenameTokenOption(label: "Sequence # (01)", value: "{sequence:01}"),
            RenameTokenOption(label: "Sequence # (001)", value: "{sequence:001}"),
            RenameTokenOption(label: "Sequence # (0001)", value: "{sequence:0001}"),
            RenameTokenOption(label: "Sequence # (00001)", value: "{sequence:00001}"),
            RenameTokenOption(label: "Image # (1)", value: "{image}"),
            RenameTokenOption(label: "Image # (01)", value: "{image:01}"),
            RenameTokenOption(label: "Image # (001)", value: "{image:001}"),
            RenameTokenOption(label: "Image # (0001)", value: "{image:0001}"),
            RenameTokenOption(label: "Image # (00001)", value: "{image:00001}"),
            RenameTokenOption(label: "Total # (1)", value: "{total}"),
            RenameTokenOption(label: "Total # (01)", value: "{total:01}"),
            RenameTokenOption(label: "Total # (001)", value: "{total:001}"),
            RenameTokenOption(label: "Total # (0001)", value: "{total:0001}"),
            RenameTokenOption(label: "Total # (00001)", value: "{total:00001}")
        ]
    }

    private var dateOptions: [RenameTokenOption] {
        [
            RenameTokenOption(label: "Date (Month DD, YYYY)", value: "{date:MMMM dd, yyyy}"),
            RenameTokenOption(label: "Date (YYYYMMDD)", value: "{date:yyyyMMdd}"),
            RenameTokenOption(label: "Date (YYMMDD)", value: "{date:yyMMdd}"),
            RenameTokenOption(label: "Date (YYYY)", value: "{date:yyyy}"),
            RenameTokenOption(label: "Date (YY)", value: "{date:yy}"),
            RenameTokenOption(label: "Date (Month)", value: "{date:MMMM}"),
            RenameTokenOption(label: "Date (Mon)", value: "{date:MMM}"),
            RenameTokenOption(label: "Date (MM)", value: "{date:MM}"),
            RenameTokenOption(label: "Date (DD)", value: "{date:dd}"),
            RenameTokenOption(label: "Julian Day of the Year", value: "{date:DDD}"),
            RenameTokenOption(label: "Hour", value: "{hour}"),
            RenameTokenOption(label: "Minute", value: "{minute}"),
            RenameTokenOption(label: "Second", value: "{second}")
        ]
    }

    private var templateTokenValues: [String] {
        (filenameOptions + copyNameOptions + sequenceOptions + dateOptions)
            .map(\.value)
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
    }

    private func tokenSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.manrope(11, weight: .bold))
                .foregroundStyle(Color.auroraFaint)
                .textCase(.uppercase)
                .tracking(0.9)
            VStack(spacing: 9, content: content)
        }
        .padding(12)
        .background(sectionBackground)
    }

    private func tokenInsertRow(
        selection: Binding<RenameTokenOption>,
        options: [RenameTokenOption],
        isEnabled: Bool = true
    ) -> some View {
        HStack(spacing: 14) {
            tokenMenu(selection: selection, options: options, isEnabled: isEnabled)
            Spacer(minLength: 14)

            insertButton("Insert", tint: .auroraCyan) { insert(selection.wrappedValue.value) }
                .disabled(!isEnabled || selection.wrappedValue.value.isEmpty)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isEnabled ? 1 : 0.48)
    }

    private func tokenMenu(
        selection: Binding<RenameTokenOption>,
        options: [RenameTokenOption],
        isEnabled: Bool
    ) -> some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection.wrappedValue = option
                } label: {
                    Text(option.label)
                }
            }
        } label: {
            HStack(spacing: 0) {
                Text(selection.wrappedValue.label)
                    .font(.manrope(12, weight: .bold))
                    .foregroundStyle(Color.auroraMagenta)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(width: 250, height: 28, alignment: .leading)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                    .strokeBorder(Color.auroraMagenta.opacity(0.45), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.auroraPanel.opacity(0.88), Color.auroraBg2.opacity(0.62)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                    .strokeBorder(Color.auroraStroke2.opacity(0.75), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 8)
    }

    private func insertButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.manrope(12, weight: .bold))
                .foregroundStyle(Color.auroraTxt)
                .frame(width: 76, height: 30)
                .background(
                    Capsule(style: .continuous)
                        .fill(tint.opacity(0.18))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(tint.opacity(0.45), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func insert(_ value: String) {
        guard !value.isEmpty else { return }
        if draftTemplate.isEmpty {
            draftTemplate = value
        } else {
            draftTemplate += value
        }
    }

}

private struct RenameTokenOption: Identifiable, Hashable {
    var id: String { label }
    let label: String
    let value: String
}

private struct RenameTemplateTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let tokenValues: [String]

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        field.textColor = NSColor(Color.auroraTxt)
        field.delegate = context.coordinator
        field.allowsEditingTextAttributes = false
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RenameTemplateTextField

        init(parent: RenameTemplateTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            shouldChangeCharactersIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard replacementString == "",
                  affectedCharRange.length > 0,
                  let tokenRange = tokenRangeToDelete(in: textView.string, affectedRange: affectedCharRange) else {
                return true
            }

            guard tokenRange != affectedCharRange else { return true }
            guard textView.shouldChangeText(in: tokenRange, replacementString: "") else { return false }
            textView.textStorage?.replaceCharacters(in: tokenRange, with: "")
            textView.didChangeText()
            parent.text = textView.string
            return false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                return deleteTokenIfNeeded(in: textView, direction: .backward)
            }
            if commandSelector == #selector(NSResponder.deleteForward(_:)) {
                return deleteTokenIfNeeded(in: textView, direction: .forward)
            }
            return false
        }

        private enum DeleteDirection {
            case backward
            case forward
        }

        private func deleteTokenIfNeeded(in textView: NSTextView, direction: DeleteDirection) -> Bool {
            let selectedRange = textView.selectedRange()
            let affectedRange: NSRange
            if selectedRange.length > 0 {
                affectedRange = selectedRange
            } else {
                switch direction {
                case .backward:
                    guard selectedRange.location > 0 else { return false }
                    affectedRange = NSRange(location: selectedRange.location - 1, length: 1)
                case .forward:
                    guard selectedRange.location < (textView.string as NSString).length else { return false }
                    affectedRange = NSRange(location: selectedRange.location, length: 1)
                }
            }

            guard let tokenRange = tokenRangeToDelete(in: textView.string, affectedRange: affectedRange) else {
                return false
            }
            guard textView.shouldChangeText(in: tokenRange, replacementString: "") else { return true }
            textView.textStorage?.replaceCharacters(in: tokenRange, with: "")
            textView.didChangeText()
            parent.text = textView.string
            return true
        }

        private func tokenRangeToDelete(in text: String, affectedRange: NSRange) -> NSRange? {
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            for token in parent.tokenValues {
                var searchStart = 0
                while searchStart < fullRange.length {
                    let searchRange = NSRange(location: searchStart, length: fullRange.length - searchStart)
                    let found = (text as NSString).range(of: token, options: [], range: searchRange)
                    guard found.location != NSNotFound else { break }
                    if rangesOverlap(found, affectedRange) || affectedRange.location == found.upperBound {
                        return found
                    }
                    searchStart = found.location + found.length
                }
            }
            return bracedTokenRangeToDelete(in: text, affectedRange: affectedRange)
        }

        private func bracedTokenRangeToDelete(in text: String, affectedRange: NSRange) -> NSRange? {
            let nsText = text as NSString
            let length = nsText.length
            guard length > 0 else { return nil }

            let probeLocation = min(max(affectedRange.location, 0), max(length - 1, 0))
            var openLocation: Int?
            if probeLocation >= 0 {
                for location in stride(from: probeLocation, through: 0, by: -1) {
                    let char = nsText.character(at: location)
                    if char == 123 { // {
                        openLocation = location
                        break
                    }
                    if char == 125 { break } // }
                }
            }
            guard let openLocation else { return nil }

            var closeLocation: Int?
            if openLocation < length {
                for location in openLocation..<length {
                    let char = nsText.character(at: location)
                    if char == 125 { // }
                        closeLocation = location
                        break
                    }
                    if location > openLocation, char == 123 { break } // next token started
                }
            }

            let end = closeLocation.map { $0 + 1 } ?? max(affectedRange.upperBound, openLocation + 1)
            let candidate = NSRange(location: openLocation, length: max(0, end - openLocation))
            guard candidate.length > 1, rangesOverlap(candidate, affectedRange) || affectedRange.location == candidate.upperBound else {
                return nil
            }
            return candidate
        }

        private func rangesOverlap(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
            lhs.location < rhs.upperBound && rhs.location < lhs.upperBound
        }
    }
}

private extension NSRange {
    var upperBound: Int { location + length }
}
