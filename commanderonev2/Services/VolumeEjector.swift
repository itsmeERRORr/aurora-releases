import Foundation
import AppKit

enum VolumeEjector {
    @MainActor
    static func eject(volumeURL: URL) async -> Bool {
        let path = volumeURL.path

        // Attempt 1: Immediate try
        var success = NSWorkspace.shared.unmountAndEjectDevice(atPath: path)
        if success { return true }

        // Attempt 2: Wait 1 second
        try? await Task.sleep(for: .seconds(1))
        success = NSWorkspace.shared.unmountAndEjectDevice(atPath: path)
        if success { return true }

        // Attempt 3: Wait 2 more seconds
        try? await Task.sleep(for: .seconds(2))
        success = NSWorkspace.shared.unmountAndEjectDevice(atPath: path)
        if success { return true }

        // Attempt 4: Force unmount using diskutil
        // This is more aggressive and should work even if processes have handles open
        try? await Task.sleep(for: .seconds(1))
        let diskIdentifier = getDiskIdentifier(for: volumeURL)
        if let disk = diskIdentifier {
            success = await forceEjectWithDiskutil(disk: disk)
            if success { return true }
        }

        // Final attempt 5: One more NSWorkspace try
        try? await Task.sleep(for: .seconds(2))
        return NSWorkspace.shared.unmountAndEjectDevice(atPath: path)
    }

    @MainActor
    private static func forceEjectWithDiskutil(disk: String) async -> Bool {
        print("🔧 Attempting force eject with diskutil for disk: \(disk)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        // Use unmountDisk instead of eject, and pass /dev/diskX
        process.arguments = ["unmountDisk", "force", "/dev/\(disk)"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()

            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            let success = process.terminationStatus == 0

            if success {
                print("✅ diskutil force unmount succeeded for \(disk)")
            } else {
                print("❌ diskutil force unmount failed for \(disk)")
                print("Exit code: \(process.terminationStatus)")
                if !stdout.isEmpty { print("stdout: \(stdout)") }
                if !stderr.isEmpty { print("stderr: \(stderr)") }
            }

            return success
        } catch {
            print("❌ Error running diskutil: \(error)")
            return false
        }
    }

    private static func getDiskIdentifier(for volumeURL: URL) -> String? {
        // Get the BSD name (disk2s1, etc.) for the volume
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", volumeURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Look for "Device Node:" line which contains the disk identifier
                for line in output.components(separatedBy: "\n") {
                    if line.contains("Device Node:") {
                        let parts = line.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                        if parts.count >= 2 {
                            let diskPath = parts[1]
                            // Extract disk2s1 from /dev/disk2s1
                            let identifier = diskPath.replacingOccurrences(of: "/dev/", with: "")
                            print("✅ Found disk identifier: \(identifier) for volume \(volumeURL.lastPathComponent)")
                            return identifier
                        }
                    }
                }
                print("❌ Could not find Device Node in diskutil output for \(volumeURL.path)")
                print("Output: \(output.prefix(500))")
            }
        } catch {
            print("❌ Error running diskutil: \(error)")
        }

        return nil
    }
}
