import AppKit
import SwiftUI

@main
struct ArgyllUXApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Avoid LaunchServices' cached bundle icon for local debug runs; read the compiled asset directly.
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let bundleIcon = NSImage(contentsOf: iconURL)
        else {
            return
        }

        bundleIcon.size = NSSize(width: 512, height: 512)
        NSApplication.shared.applicationIconImage = bundleIcon
    }

    var body: some Scene {
        WindowGroup("ArgyllUX") {
            AppShellView(model: model)
                .frame(minWidth: 1200, minHeight: 820)
        }
        .defaultSize(width: 1440, height: 900)

        Window("CLI Transcript", id: CliTranscriptWindowView.windowID) {
            CliTranscriptWindowView(transcript: model.cliTranscript)
        }
        .defaultSize(width: 920, height: 520)
    }
}
