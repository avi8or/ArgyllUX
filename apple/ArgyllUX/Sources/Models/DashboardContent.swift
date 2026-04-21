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

    static func deleteAccessibilityLabel(for jobTitle: String, jobId: String) -> String {
        "Delete Active Work: \(deleteTargetLabel(jobTitle: jobTitle, jobId: jobId))"
    }

    static func deletionConfirmationMessage(jobTitle: String, jobId: String) -> String {
        if let genericTarget = genericDraftDeleteTarget(jobTitle: jobTitle, jobId: jobId) {
            return "This removes \(genericTarget) and its unpublished working files."
        }

        let trimmedTitle = jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return "This removes job \(jobId) and its unpublished working files."
        }

        return "This removes \"\(trimmedTitle)\" and its unpublished working files."
    }

    private static func deleteTargetLabel(jobTitle: String, jobId: String) -> String {
        genericDraftDeleteTarget(jobTitle: jobTitle, jobId: jobId)
            ?? jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func genericDraftDeleteTarget(jobTitle: String, jobId: String) -> String? {
        let trimmedTitle = jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty || trimmedTitle.caseInsensitiveCompare("New Profile") == .orderedSame else {
            return nil
        }

        let label = trimmedTitle.isEmpty ? "New Profile" : trimmedTitle
        return "\(label) (\(jobId))"
    }
}

enum PrinterProfileCopy {
    static let deleteActionTitle = "Delete Printer Profile"
    static let deleteErrorTitle = "Couldn't Delete Printer Profile"

    static func deletionConfirmationMessage(profileName: String) -> String {
        let trimmedName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return "This removes the Printer Profile from the library and returns the source job to review."
        }

        return "This removes \"\(trimmedName)\" from Printer Profiles and returns the source job to review."
    }
}

struct ProfileHealthItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let context: String
    let result: String
}
