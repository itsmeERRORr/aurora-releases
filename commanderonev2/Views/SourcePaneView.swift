import SwiftUI

struct SourcePaneView: View {
    @Bindable var appState: AppState
    let volumeWatcher: VolumeWatcher

    @State private var sourceFiles: [URL] = []
    @State private var isScanning = false
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "externaldrive.fill")
                    .foregroundStyle(Color.accentGreen)
                Text("Source")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                if let vol = appState.activeVolume {
                    Label("\(vol.rawFileCount) RAW", systemImage: "photo.on.rectangle")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)

                    Button {
                        withAnimation {
                            isRefreshing = true
                        }
                        refreshSourceFiles()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(.linear(duration: 0.6).repeatCount(isRefreshing ? 3 : 0, autoreverses: false), value: isRefreshing)
                    }
                    .buttonStyle(IconButtonStyle())
                    .disabled(isRefreshing)

                    Button {
                        volumeWatcher.selectManualSource()
                    } label: {
                        Text("Change")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.primaryPurple)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.bgMedium)

            Divider()

            if appState.mountedVolumes.isEmpty {
                // No volumes
                VStack(spacing: 16) {
                    Image(systemName: "sdcard")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.textTertiary)
                    Text("No Source Selected")
                        .font(.title3)
                        .foregroundStyle(Color.textSecondary)
                    Text("Insert SD card or select a folder manually")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)

                    Button {
                        volumeWatcher.selectManualSource()
                    } label: {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                            Text("Select Folder")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bgDark)
            } else {
                // Volume list
                List(selection: Binding(
                    get: { appState.activeVolume?.id },
                    set: { id in
                        if let id, let vol = appState.mountedVolumes.first(where: { $0.id == id }) {
                            appState.activeVolume = vol
                            refreshSourceFiles()
                        }
                    }
                )) {
                    Section("Volumes") {
                        ForEach(appState.mountedVolumes) { volume in
                            HStack {
                                Image(systemName: volume.isActive ? "sdcard.fill" : "externaldrive")
                                    .foregroundStyle(volume.isActive ? Color.accentGreen : Color.textSecondary)
                                VStack(alignment: .leading) {
                                    Text(volume.name)
                                        .fontWeight(volume.isActive ? .semibold : .regular)
                                        .foregroundColor(.textPrimary)
                                    Text(volume.path.path)
                                        .font(.caption2)
                                        .foregroundStyle(Color.textTertiary)
                                }
                                Spacer()
                                if volume.rawFileCount > 0 {
                                    Text("\(volume.rawFileCount)")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentGreen)
                                        .clipShape(Capsule())
                                }
                            }
                            .tag(volume.id)
                        }
                    }

                    if !sourceFiles.isEmpty {
                        Section("Files (\(sourceFiles.count))") {
                            ForEach(sourceFiles, id: \.path) { file in
                                HStack {
                                    Image(systemName: "doc.fill")
                                        .foregroundStyle(Color.primaryPurple)
                                    VStack(alignment: .leading) {
                                        Text(file.lastPathComponent)
                                            .font(.mono(12))
                                            .foregroundColor(.textPrimary)
                                        Text(fileSizeString(file))
                                            .font(.caption2)
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(Color.bgDark)
            }
        }
        .onChange(of: appState.activeVolume) { _, newVolume in
            if newVolume != nil {
                refreshSourceFiles()
            }
        }
        .onAppear {
            refreshSourceFiles()
        }
    }

    private func refreshSourceFiles() {
        guard let vol = appState.activeVolume else {
            sourceFiles = []
            isRefreshing = false
            return
        }
        isScanning = true
        Task {
            let files = volumeWatcher.listRawFiles(at: vol.path)
            sourceFiles = files
            isScanning = false

            // Add a small delay for animation visibility
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation {
                isRefreshing = false
            }
        }
    }

    private func fileSizeString(_ url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? Int64) ?? 0
        let mb = Double(size) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }
}
