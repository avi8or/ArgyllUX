import AppKit

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
}
