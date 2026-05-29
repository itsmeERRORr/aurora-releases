import SwiftUI

struct DestinationPaneView: View {
    @Bindable var appState: AppState

    @State private var destFiles: [URL] = []
    @State private var showFolderPicker = false
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.primaryPurple)
                Text("Destination")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Button("Choose...") {
                    chooseDestination()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.bgMedium)

            Divider()

            if let dest = appState.destinationURL {
                // Show destination path
                HStack {
                    Image(systemName: "folder.badge.checkmark")
                        .foregroundStyle(Color.accentGreen)
                    Text(dest.path)
                        .font(.mono(11))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        withAnimation {
                            isRefreshing = true
                        }
                        refreshDestFiles()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(.linear(duration: 0.6).repeatCount(isRefreshing ? 3 : 0, autoreverses: false), value: isRefreshing)
                    }
                    .buttonStyle(IconButtonStyle())
                    .disabled(isRefreshing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.glassBase)

                Divider()

                // File list
                if destFiles.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 30))
                            .foregroundStyle(Color.textTertiary)
                        Text("Destination is empty")
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.bgDark)
                } else {
                    List {
                        Section("Files (\(destFiles.count))") {
                            ForEach(destFiles, id: \.path) { file in
                                HStack {
                                    Image(systemName: file.hasDirectoryPath ? "folder.fill" : "doc.fill")
                                        .foregroundStyle(file.hasDirectoryPath ? Color.primaryPurple : Color.accentGreen)
                                    Text(file.lastPathComponent)
                                        .font(.mono(12))
                                        .foregroundColor(.textPrimary)
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .background(Color.bgDark)
                }
            } else {
                // No destination
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.textTertiary)
                    Text("No destination selected")
                        .font(.title3)
                        .foregroundStyle(Color.textSecondary)
                    Button("Choose Destination...") {
                        chooseDestination()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bgDark)
            }
        }
        .onAppear {
            refreshDestFiles()
        }
        .onChange(of: appState.destinationURL) { _, _ in
            refreshDestFiles()
        }
        .onChange(of: appState.importState) { _, newState in
            if newState == .done {
                refreshDestFiles()
            }
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the destination folder for imported photos"
        panel.prompt = "Select Destination"

        if panel.runModal() == .OK, let url = panel.url {
            // Save bookmark
            if let bookmarkData = BookmarkManager.saveBookmark(for: url) {
                appState.destinationBookmarkData = bookmarkData
            }
            appState.destinationURL = url
            appState.log("Destination set: \(url.path)")
        }
    }

    private func refreshDestFiles() {
        guard let dest = appState.destinationURL else {
            destFiles = []
            isRefreshing = false
            return
        }

        Task {
            let accessing = BookmarkManager.startAccessing(dest)
            defer { if accessing { BookmarkManager.stopAccessing(dest) } }

            let fm = FileManager.default
            if let contents = try? fm.contentsOfDirectory(
                at: dest,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                destFiles = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
            } else {
                destFiles = []
            }

            // Add a small delay for animation visibility
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation {
                isRefreshing = false
            }
        }
    }
}
