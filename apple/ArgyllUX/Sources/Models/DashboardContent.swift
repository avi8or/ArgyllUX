import Foundation

enum LauncherActionKind: Hashable {
    case newProfile
    case route(AppRoute)
    case planned
}

struct LauncherAction: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let detail: String
    let status: String
    let kind: LauncherActionKind

    var isEnabled: Bool {
        switch kind {
        case .newProfile, .route:
            true
        case .planned:
            false
        }
    }
}

extension LauncherAction {
    var plannedDescriptor: PlannedActionDescriptor? {
        guard case .planned = kind else { return nil }

        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = trimmedDetail.isEmpty
            ? "Not runnable in this build."
            : "\(trimmedDetail) Not runnable in this build."

        return PlannedActionDescriptor(title: title, message: message)
    }
}

enum ShellJumpDestination: Hashable {
    case route(AppRoute)
    case newProfileJob(String)
    case printerProfile(String)
    case settings(SettingsCatalogSelection)
}

struct ShellJumpItem: Identifiable, Hashable {
    let title: String
    let subtitle: String
    let systemImage: String
    let destination: ShellJumpDestination

    var id: String {
        "\(title)|\(subtitle)|\(systemImage)|\(destination)"
    }
}

struct PlannedActionDescriptor: Identifiable, Hashable {
    let title: String
    let message: String

    var id: String {
        "\(title)|\(message)"
    }

    var status: String {
        "Planned"
    }

    var accessibilityLabel: String {
        "\(title). Planned. \(message)"
    }

    var help: String {
        message
    }
}

struct WorkflowProgressItem: Identifiable, Hashable {
    let stage: WorkflowStage
    let title: String
    let state: WorkflowStageState

    var id: WorkflowStage {
        stage
    }

    var status: String {
        switch state {
        case .completed:
            "Done"
        case .current:
            "Current"
        case .upcoming:
            "Not started"
        case .blocked:
            "Blocked"
        }
    }
}

struct WorkflowPrimaryActionPresentation: Equatable {
    let title: String
    let isEnabled: Bool
    let disabledReason: String?
}

func workflowProgressItems(for detail: NewProfileJobDetail) -> [WorkflowProgressItem] {
    detail.stageTimeline.map { item in
        WorkflowProgressItem(
            stage: item.stage,
            title: workflowStageDisplayTitle(item.stage),
            state: item.state
        )
    }
}

func workflowStageDisplayTitle(_ stage: WorkflowStage) -> String {
    switch stage {
    case .context:
        "Profile Setup"
    case .target:
        "Target Planning"
    case .print:
        "Print Target"
    case .drying:
        "Drying"
    case .measure:
        "Measure Target"
    case .build:
        "Build Profile"
    case .review:
        "Review"
    case .publish:
        "Publish"
    case .completed:
        "Completed"
    case .blocked:
        "Blocked"
    case .failed:
        "Failed"
    }
}

func workflowNextActionDisplayTitle(
    stage: WorkflowStage,
    rawTitle: String,
    hasMeasurementCheckpoint: Bool = false
) -> String {
    switch stage {
    case .context:
        "Continue"
    case .target:
        "Generate Target"
    case .print:
        "Mark Chart as Printed"
    case .drying:
        "Mark Ready to Measure"
    case .measure:
        hasMeasurementCheckpoint ? "Resume Measurement" : "Measure"
    case .build:
        "Build Profile"
    case .review, .publish:
        "Publish"
    case .completed:
        rawTitle.isEmpty ? "Open in Printer Profiles" : rawTitle
    case .blocked, .failed:
        rawTitle.isEmpty ? "Review Blocking Error" : rawTitle
    }
}

func workflowNextActionDisplayTitle(_ detail: NewProfileJobDetail) -> String {
    workflowNextActionDisplayTitle(
        stage: detail.stage,
        rawTitle: detail.nextAction,
        hasMeasurementCheckpoint: detail.measurement.hasMeasurementCheckpoint
    )
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
