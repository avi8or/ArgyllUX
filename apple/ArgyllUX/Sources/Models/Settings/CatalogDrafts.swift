import Foundation

let curatedPaperSurfaceClasses = [
    "Matte",
    "Luster",
    "Glossy",
    "Baryta",
    "Canvas",
]

extension ColorantFamily {
    static let structuredCases: [ColorantFamily] = [.grayK, .rgb, .cmy, .cmyk, .extendedN]

    var displayLabel: String {
        switch self {
        case .grayK:
            "1 channel (Gray/K)"
        case .rgb:
            "3 channel RGB"
        case .cmy:
            "3 channel CMY"
        case .cmyk:
            "4 channel CMYK"
        case .extendedN:
            "Extended N-color"
        }
    }

    var fixedChannelCount: UInt32? {
        switch self {
        case .grayK:
            1
        case .rgb, .cmy:
            3
        case .cmyk:
            4
        case .extendedN:
            nil
        }
    }

    func hasBlackChannel(channelLabels: [String]) -> Bool {
        switch self {
        case .grayK, .cmyk:
            true
        case .extendedN:
            channelLabels.contains { label in
                let lowered = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return lowered == "k" || lowered == "black"
            }
        case .rgb, .cmy:
            false
        }
    }
}

struct PrinterDraft: Equatable {
    var id: String?
    var manufacturer = ""
    var model = ""
    var nickname = ""
    var transportStyle = ""
    var colorantFamily: ColorantFamily = .cmyk
    var channelCount: UInt32 = 4
    var channelLabels: [String] = []
    var supportedMediaSettings: [String] = []
    var supportedQualityModes: [String] = []
    var monochromePathNotes = ""
    var notes = ""

    init() {}

    init(record: PrinterRecord) {
        id = record.id
        manufacturer = record.manufacturer
        model = record.model
        nickname = record.nickname
        transportStyle = record.transportStyle
        colorantFamily = record.colorantFamily
        channelCount = record.channelCount
        channelLabels = record.channelLabels
        supportedMediaSettings = record.supportedMediaSettings
        supportedQualityModes = record.supportedQualityModes
        monochromePathNotes = record.monochromePathNotes
        notes = record.notes
    }

    var normalizedChannelCount: UInt32 {
        colorantFamily.fixedChannelCount ?? channelCount
    }

    var hasBlackChannel: Bool {
        colorantFamily.hasBlackChannel(channelLabels: channelLabels)
    }

    var title: String {
        if let id, !id.isEmpty {
            return "Edit Printer"
        }

        return "New Printer"
    }
}

struct PaperDraft: Equatable {
    var id: String?
    var manufacturer = ""
    var paperLine = ""
    var surfaceClassSelection = ""
    var surfaceClassOther = ""
    var basisWeightValue = ""
    var basisWeightUnit: PaperWeightUnit = .unspecified
    var thicknessValue = ""
    var thicknessUnit: PaperThicknessUnit = .unspecified
    var surfaceTexture = ""
    var baseMaterial = ""
    var mediaColor = ""
    var opacity = ""
    var whiteness = ""
    var obaContent = ""
    var inkCompatibility = ""
    var notes = ""

    init() {}

    init(record: PaperRecord) {
        id = record.id
        manufacturer = record.manufacturer
        paperLine = record.paperLine
        if record.surfaceClass.isEmpty || curatedPaperSurfaceClasses.contains(record.surfaceClass) {
            surfaceClassSelection = record.surfaceClass
            surfaceClassOther = ""
        } else {
            surfaceClassSelection = "Other"
            surfaceClassOther = record.surfaceClass
        }
        basisWeightValue = record.basisWeightValue
        basisWeightUnit = record.basisWeightUnit
        thicknessValue = record.thicknessValue
        thicknessUnit = record.thicknessUnit
        surfaceTexture = record.surfaceTexture
        baseMaterial = record.baseMaterial
        mediaColor = record.mediaColor
        opacity = record.opacity
        whiteness = record.whiteness
        obaContent = record.obaContent
        inkCompatibility = record.inkCompatibility
        notes = record.notes
    }

    var surfaceClass: String {
        if surfaceClassSelection == "Other" {
            return surfaceClassOther.trimmed
        }
        return surfaceClassSelection.trimmed
    }

    var title: String {
        if let id, !id.isEmpty {
            return "Edit Paper"
        }

        return "New Paper"
    }
}

struct PrinterPaperPresetDraft: Equatable {
    var id: String?
    var printerId: String?
    var paperId: String?
    var label = ""
    var printPath = ""
    var mediaSetting = ""
    var qualityMode = ""
    var totalInkLimitPercentText = ""
    var blackInkLimitPercentText = ""
    var notes = ""

    init() {}

    init(record: PrinterPaperPresetRecord) {
        id = record.id
        printerId = record.printerId
        paperId = record.paperId
        label = record.label
        printPath = record.printPath
        mediaSetting = record.mediaSetting
        qualityMode = record.qualityMode
        totalInkLimitPercentText = record.totalInkLimitPercent.map(String.init) ?? ""
        blackInkLimitPercentText = record.blackInkLimitPercent.map(String.init) ?? ""
        notes = record.notes
    }

    var totalInkLimitPercent: UInt32? {
        let trimmed = totalInkLimitPercentText.trimmed
        return trimmed.isEmpty ? nil : UInt32(trimmed)
    }

    var blackInkLimitPercent: UInt32? {
        let trimmed = blackInkLimitPercentText.trimmed
        return trimmed.isEmpty ? nil : UInt32(trimmed)
    }

    var title: String {
        if let id, !id.isEmpty {
            return "Edit Printer and Paper Settings"
        }
        return "New Printer and Paper Settings"
    }
}

func sanitizePrinterPaperPresetDraft(
    _ draft: inout PrinterPaperPresetDraft,
    selectedPrinter: PrinterRecord?
) {
    let availableMediaSettings = selectedPrinter?.supportedMediaSettings ?? []
    let availableQualityModes = selectedPrinter?.supportedQualityModes ?? []
    let hasBlackChannel = selectedPrinter?.colorantFamily.hasBlackChannel(
        channelLabels: selectedPrinter?.channelLabels ?? []
    ) ?? false

    if !availableMediaSettings.contains(draft.mediaSetting) {
        draft.mediaSetting = ""
    }

    if !availableQualityModes.contains(draft.qualityMode) {
        draft.qualityMode = ""
    }

    if !hasBlackChannel {
        draft.blackInkLimitPercentText = ""
    }
}

func sanitizePrinterPaperPresetDraft(
    _ draft: inout PrinterPaperPresetDraft,
    printers: [PrinterRecord]
) {
    let selectedPrinter = printers.first(where: { $0.id == draft.printerId })
    sanitizePrinterPaperPresetDraft(&draft, selectedPrinter: selectedPrinter)
}
