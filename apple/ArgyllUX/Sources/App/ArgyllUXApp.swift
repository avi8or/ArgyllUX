import SwiftUI

@main
struct ArgyllUXApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("ArgyllUX") {
            AppShellView(model: model)
                .frame(minWidth: 1200, minHeight: 820)
        }
        .defaultSize(width: 1440, height: 900)
    }
}
