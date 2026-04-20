import Foundation

struct LauncherAction: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let detail: String
}

struct ActiveWorkItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let nextAction: String
}

struct ProfileHealthItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let context: String
    let result: String
}
