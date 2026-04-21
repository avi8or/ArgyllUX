import AppKit
import Foundation

protocol FileOpening {
    func revealPathInFinder(_ path: String)
    func openPath(_ path: String)
}

final class FileOpener: FileOpening {
    func revealPathInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openPath(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
