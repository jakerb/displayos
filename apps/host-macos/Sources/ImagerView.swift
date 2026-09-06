import AppKit
import SwiftUI

struct ImagerView: View {
    @State private var isoPath = ""
    @State private var drives: [TargetDrive] = []
    @State private var selectedDeviceID = ""
    @State private var message = "Select the ISO and a removable USB drive."
    @State private var showingConfirm = false

    private var selectedDrive: TargetDrive? {
        drives.first { $0.id == selectedDeviceID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Create DisplayOS USB").font(.title.bold())
            Text("This writes the Intel iMac receiver image to a USB drive. Every file on that drive will be erased.").foregroundStyle(.secondary)
            HStack {
                TextField("ISO path", text: $isoPath)
                Button("Choose…") { chooseISO() }
            }
            HStack {
                Picker("Target USB drive", selection: $selectedDeviceID) {
                    Text(drives.isEmpty ? "No removable drives found" : "Choose a removable drive").tag("")
                    ForEach(drives) { drive in
                        Text(drive.label).tag(drive.id)
                    }
                }
                .frame(maxWidth: .infinity)
                Button { refreshDrives() } label: {
                    Label("Refresh drives", systemImage: "arrow.clockwise")
                }
            }
            Button("Write bootable USB", role: .destructive) { showingConfirm = true }
                .disabled(isoPath.isEmpty || selectedDrive == nil)
            Text(message).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .task { refreshDrives() }
        .alert("Erase and write this USB drive?", isPresented: $showingConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Erase and write", role: .destructive) { writeImage() }
        } message: {
            Text("This will permanently erase \(selectedDrive?.label ?? "the selected drive").")
        }
    }

    private func chooseISO() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { isoPath = panel.url?.path ?? "" }
    }

    private func refreshDrives() {
        do {
            let diskIDs = try diskutilPlist(arguments: ["list"])["AllDisks"] as? [String] ?? []
            drives = try diskIDs.compactMap { diskID in
                let info = try diskutilPlist(arguments: ["info", diskID])
                guard info["WholeDisk"] as? Bool == true,
                      info["Internal"] as? Bool == false,
                      info["RemovableMedia"] as? Bool == true,
                      let identifier = info["DeviceIdentifier"] as? String else { return nil }
                let name = (info["MediaName"] as? String) ?? (info["VolumeName"] as? String) ?? "External drive"
                let size = ByteCountFormatter.string(fromByteCount: (info["DiskSize"] as? Int64) ?? 0, countStyle: .file)
                return TargetDrive(id: identifier, name: name, size: size)
            }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            if !drives.contains(where: { $0.id == selectedDeviceID }) { selectedDeviceID = "" }
            message = drives.isEmpty ? "No removable USB drives found. Insert one, then refresh." : "Select the ISO and the USB drive to erase."
        } catch {
            drives = []
            selectedDeviceID = ""
            message = "Could not discover removable drives: \(error.localizedDescription)"
        }
    }

    private func writeImage() {
        guard let drive = selectedDrive else { return }
        message = "Writing requires administrator approval…"
        let escapedISOPath = isoPath.replacingOccurrences(of: "'", with: "'\\\"'\\\"'")
        let command = "diskutil unmountDisk /dev/\(drive.id) && dd if='\(escapedISOPath)' of=/dev/r\(drive.id) bs=4m status=progress && diskutil eject /dev/\(drive.id)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(command.replacingOccurrences(of: "\\\"", with: "\\\\\\\""))\" with administrator privileges"]
        do {
            try process.run()
            process.waitUntilExit()
            message = process.terminationStatus == 0 ? "USB written and ejected." : "Writing failed. Confirm the ISO and USB drive, then try again."
        } catch {
            message = "Could not start the writer: \(error.localizedDescription)"
        }
    }

    private func diskutilPlist(arguments: [String]) throws -> [String: Any] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments + ["-plist"]
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw DiskDiscoveryError.diskutilFailed }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
    }
}

private struct TargetDrive: Identifiable {
    let id: String
    let name: String
    let size: String

    var label: String { "\(name) (\(size)) — /dev/\(id)" }
}

private enum DiskDiscoveryError: LocalizedError {
    case diskutilFailed

    var errorDescription: String? { "diskutil did not return drive information." }
}
