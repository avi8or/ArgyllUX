import Foundation

func isPrinterDraftValid(_ draft: PrinterDraft) -> Bool {
    !draft.manufacturer.trimmed.isEmpty &&
        !draft.model.trimmed.isEmpty &&
        (draft.colorantFamily != .extendedN || (6 ... 15).contains(draft.channelCount))
}

func isPaperDraftValid(_ draft: PaperDraft) -> Bool {
    !draft.paperLine.trimmed.isEmpty &&
        (draft.surfaceClassSelection != "Other" || !draft.surfaceClassOther.trimmed.isEmpty)
}

func structuredPrinterIdentity(_ printer: PrinterRecord) -> String {
    let manufacturer = printer.manufacturer.trimmed
    let model = printer.model.trimmed
    let base = [manufacturer, model].filter { !$0.isEmpty }.joined(separator: " ")
    if printer.nickname.trimmed.isEmpty {
        return base
    }
    return "\(base) • \(printer.nickname)"
}

func structuredPaperIdentity(_ paper: PaperRecord) -> String {
    [paper.manufacturer.trimmed, paper.paperLine.trimmed]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

func paperSurfaceSummary(_ paper: PaperRecord) -> String? {
    let parts = [paper.surfaceClass.trimmed, paper.surfaceTexture.trimmed].filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: " • ")
}

func paperSpecsSummary(_ paper: PaperRecord) -> String? {
    let parts = [
        paperMeasurementSummary(value: paper.basisWeightValue, unitLabel: paper.basisWeightUnit.summaryLabel),
        paperMeasurementSummary(value: paper.thicknessValue, unitLabel: paper.thicknessUnit.summaryLabel),
    ].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " • ")
}

func paperDetailsSummary(_ paper: PaperRecord) -> String? {
    let parts = [
        paper.baseMaterial.trimmed,
        paper.mediaColor.trimmed,
        paper.opacity.trimmed.isEmpty ? "" : "Opacity \(paper.opacity.trimmed)",
        paper.whiteness.trimmed.isEmpty ? "" : "Whiteness \(paper.whiteness.trimmed)",
        paper.obaContent.trimmed.isEmpty ? "" : "OBA \(paper.obaContent.trimmed)",
        paper.inkCompatibility.trimmed,
    ].filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: " • ")
}

func paperMeasurementSummary(value: String, unitLabel: String?) -> String? {
    let trimmedValue = value.trimmed
    guard !trimmedValue.isEmpty else { return nil }
    guard let unitLabel, !unitLabel.isEmpty else { return trimmedValue }
    return "\(trimmedValue) \(unitLabel)"
}

func channelSetupSummary(_ family: ColorantFamily, _ channelCount: UInt32, _ channelLabels: [String]) -> String {
    var parts = [family.displayLabel]
    if family == .extendedN {
        parts.append("\(channelCount) channels")
        if !channelLabels.isEmpty {
            parts.append(channelLabels.joined(separator: ", "))
        }
    }
    return parts.joined(separator: " • ")
}

func presetLimitsSummary(_ preset: PrinterPaperPresetRecord) -> String? {
    var parts: [String] = []
    if let totalInkLimitPercent = preset.totalInkLimitPercent {
        parts.append("TAC \(totalInkLimitPercent)%")
    }
    if let blackInkLimitPercent = preset.blackInkLimitPercent {
        parts.append("Black \(blackInkLimitPercent)%")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " • ")
}

extension PaperWeightUnit {
    var pickerLabel: String {
        switch self {
        case .unspecified:
            "Unit"
        case .gsm:
            "gsm"
        case .lb:
            "lb"
        }
    }

    var summaryLabel: String? {
        switch self {
        case .unspecified:
            nil
        case .gsm:
            "gsm"
        case .lb:
            "lb"
        }
    }
}

extension PaperThicknessUnit {
    var pickerLabel: String {
        switch self {
        case .unspecified:
            "Unit"
        case .mil:
            "mil"
        case .mm:
            "mm"
        case .micron:
            "micron"
        }
    }

    var summaryLabel: String? {
        switch self {
        case .unspecified:
            nil
        case .mil:
            "mil"
        case .mm:
            "mm"
        case .micron:
            "micron"
        }
    }
}
