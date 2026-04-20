import Foundation

enum LauncherActionKind: Hashable {
    case newProfile
    case placeholder
}

struct LauncherAction: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let detail: String
    let kind: LauncherActionKind
}

enum ActiveWorkCopy {
    static let emptyStateMessage = "No active or resumable work yet."
    static let deleteActionTitle = "Delete Active Work"
    static let deleteErrorTitle = "Couldn't Delete Active Work"
    static let deleteHint = "Removes this unpublished work and its working files."

    static func deleteAccessibilityLabel(for jobTitle: String) -> String {
        "Delete Active Work: \(jobTitle)"
    }

    static func deletionConfirmationMessage(jobTitle: String) -> String {
        let trimmedTitle = jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return "This removes the unpublished job and its working files."
        }

        return "This removes \"\(trimmedTitle)\" and its unpublished working files."
    }
}

struct ProfileHealthItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let context: String
    let result: String
}
