import AppKit
import Foundation

enum ExiftoolInstallerService {
    static func installedExiftoolPath() -> String? {
        let fm = FileManager.default
        if let bundled = Bundle.main.path(forResource: "exiftool", ofType: nil) {
            let libPath = (bundled as NSString).deletingLastPathComponent
                .appending("/lib/Image/ExifTool.pm")
            if fm.fileExists(atPath: libPath) {
                return bundled
            }
        }

        for path in ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "/usr/bin/exiftool"] {
            if fm.fileExists(atPath: path) { return path }
        }
        return nil
    }

    static var isInstalled: Bool {
        installedExiftoolPath() != nil
    }

    @discardableResult
    static func openHomebrewInstallerInTerminal() -> Bool {
        let script = """
        #!/bin/zsh
        set -e
        clear

        echo "Aurora ExifTool installer"
        echo "This will install Homebrew if needed, then install exiftool."
        echo ""

        if ! command -v brew >/dev/null 2>&1; then
          echo "Homebrew not found. Installing Homebrew..."
          /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi

        if [[ -x /opt/homebrew/bin/brew ]]; then
          eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -x /usr/local/bin/brew ]]; then
          eval "$(/usr/local/bin/brew shellenv)"
        fi

        if ! command -v brew >/dev/null 2>&1; then
          echo ""
          echo "Homebrew installation finished, but brew is not available in this shell."
          echo "Close this window and try the Aurora install button again."
          echo ""
          read -k 1 "?Press any key to close..."
          exit 1
        fi

        echo "Installing exiftool..."
        brew install exiftool

        echo ""
        echo "ExifTool installed successfully. Returning to Aurora..."
        echo ""
        (sleep 2; osascript -e 'tell application "Terminal" to close front window' >/dev/null 2>&1) &
        exit 0
        """

        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("aurora-install-exiftool-")
                .appendingPathExtension(UUID().uuidString)
                .appendingPathExtension("command")
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return NSWorkspace.shared.open(url)
        } catch {
            return false
        }
    }
}
