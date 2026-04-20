import Foundation

struct StoragePaths: Equatable {
    let appSupportPath: String
    let databasePath: String
    let logPath: String

    static func `default`() -> StoragePaths {
        let fileManager = FileManager.default
        let appSupportRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let logsRoot = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!

        let appSupportURL = appSupportRoot.appendingPathComponent("ArgyllUX", isDirectory: true)
        let logDirectoryURL = logsRoot.appendingPathComponent("Logs/ArgyllUX", isDirectory: true)

        return StoragePaths(
            appSupportPath: appSupportURL.path,
            databasePath: appSupportURL.appendingPathComponent("argyllux.sqlite").path,
            logPath: logDirectoryURL.appendingPathComponent("engine.log").path
        )
    }

    static func fixture(root: URL) -> StoragePaths {
        let appSupportURL = root.appendingPathComponent("Application Support/ArgyllUX", isDirectory: true)
        let logURL = root.appendingPathComponent("Logs/ArgyllUX/engine.log", isDirectory: false)

        return StoragePaths(
            appSupportPath: appSupportURL.path,
            databasePath: appSupportURL.appendingPathComponent("argyllux.sqlite").path,
            logPath: logURL.path
        )
    }

    func makeConfig(argyllOverridePath: String?) -> EngineConfig {
        EngineConfig(
            appSupportPath: appSupportPath,
            databasePath: databasePath,
            logPath: logPath,
            argyllOverridePath: argyllOverridePath,
            additionalSearchRoots: []
        )
    }
}
