import Foundation
import Testing
@testable import ArgyllUX

@MainActor
struct AppModelTests {
    @Test
    func bootstrapLoadsToolchainAndHealth() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let fakeEngine = FakeEngine(
            bootstrapStatus: BootstrapStatus(
                appSupportDirReady: true,
                databaseInitialized: true,
                migrationsApplied: true,
                toolchainStatus: ToolchainStatus(
                    state: .ready,
                    resolvedInstallPath: "/opt/homebrew/bin",
                    discoveredExecutables: ["targen", "printtarg"],
                    missingExecutables: [],
                    lastValidationTime: "2026-04-19T18:30:00Z"
                )
            ),
            appHealth: AppHealth(
                readiness: "ready",
                blockingIssues: [],
                warnings: ["Storage location: /tmp/ArgyllUX"]
            ),
            logs: [
                LogEntry(
                    timestamp: "2026-04-19T18:30:00Z",
                    level: "info",
                    message: "Bootstrap completed.",
                    source: "engine.bootstrap"
                )
            ]
        )

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.bootstrapIfNeeded()

        #expect(fakeEngine.bootstrapCallCount == 1)
        #expect(model.toolchainStatus?.state == .ready)
        #expect(model.appHealth?.readiness == "ready")
        #expect(model.detectedToolchainPath == "/opt/homebrew/bin")
        #expect(model.recentLogs.count == 1)
        #expect(model.toolchainPathInput == "/opt/homebrew/bin")
    }

    @Test
    func applyToolchainPathPassesTrimmedOverride() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let fakeEngine = FakeEngine(
            bootstrapStatus: BootstrapStatus(
                appSupportDirReady: true,
                databaseInitialized: true,
                migrationsApplied: false,
                toolchainStatus: ToolchainStatus(
                    state: .notFound,
                    resolvedInstallPath: nil,
                    discoveredExecutables: [],
                    missingExecutables: ["targen"],
                    lastValidationTime: "2026-04-19T18:35:00Z"
                )
            ),
            appHealth: AppHealth(
                readiness: "attention",
                blockingIssues: ["ArgyllCMS is missing required tools: targen."],
                warnings: []
            ),
            logs: []
        )
        fakeEngine.setToolchainPathResult = ToolchainStatus(
            state: .partial,
            resolvedInstallPath: "/Applications/ArgyllCMS/bin",
            discoveredExecutables: ["targen", "printtarg"],
            missingExecutables: ["chartread"],
            lastValidationTime: "2026-04-19T18:36:00Z"
        )

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        model.toolchainPathInput = "   /Applications/ArgyllCMS   "
        await model.applyToolchainPath()

        #expect(fakeEngine.lastSetToolchainPath == "/Applications/ArgyllCMS")
        #expect(model.toolchainStatus?.state == .partial)
        #expect(model.bootstrapStatus == nil)
    }
}

private final class FakeEngine: EngineProtocol, @unchecked Sendable {
    private(set) var bootstrapCallCount = 0
    private(set) var lastSetToolchainPath: String?

    private let bootstrapStatusValue: BootstrapStatus
    private let appHealthValue: AppHealth
    private let logsValue: [LogEntry]

    var setToolchainPathResult: ToolchainStatus

    init(
        bootstrapStatus: BootstrapStatus,
        appHealth: AppHealth,
        logs: [LogEntry]
    ) {
        self.bootstrapStatusValue = bootstrapStatus
        self.appHealthValue = appHealth
        self.logsValue = logs
        self.setToolchainPathResult = bootstrapStatus.toolchainStatus
    }

    func bootstrap(config: EngineConfig) -> BootstrapStatus {
        bootstrapCallCount += 1
        return bootstrapStatusValue
    }

    func getAppHealth() -> AppHealth {
        appHealthValue
    }

    func getRecentLogs(limit: UInt32) -> [LogEntry] {
        Array(logsValue.prefix(Int(limit)))
    }

    func getToolchainStatus() -> ToolchainStatus {
        setToolchainPathResult
    }

    func setToolchainPath(path: String?) -> ToolchainStatus {
        lastSetToolchainPath = path
        return setToolchainPathResult
    }
}
