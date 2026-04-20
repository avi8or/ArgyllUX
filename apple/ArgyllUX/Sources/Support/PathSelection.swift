import AppKit
import UniformTypeIdentifiers

enum PathSelection {
    @MainActor
    static func chooseDirectory(initialPath: String?) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose Path"

        if let initialPath, !initialPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: initialPath, isDirectory: true)
        }

        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    @MainActor
    static func chooseFile(initialPath: String?, allowedExtensions: [String]) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Choose File"

        if let initialPath, !initialPath.isEmpty {
            let url = URL(fileURLWithPath: initialPath)
            panel.directoryURL = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        }

        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
