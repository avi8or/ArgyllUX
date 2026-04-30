import SwiftUI

/// Centralizes semantic typography roles for shell, workflow, and trust surfaces.
enum AppTypography {
    static let shellNavigation = Font.body
    static let shellUtility = Font.callout
    static let statusBadge = Font.callout.weight(.semibold)
    static let activeWorkTitle = Font.body.weight(.semibold)
    static let activeWorkStage = Font.callout.weight(.semibold)
    static let activeWorkSupporting = Font.callout
    static let detailLabel = Font.callout.weight(.semibold)
    static let detailValue = Font.body
    static let trustSummarySupporting = Font.callout
    static let readableMetadata = Font.callout
}
