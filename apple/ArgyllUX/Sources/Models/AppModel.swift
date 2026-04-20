import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedRoute: AppRoute = .home
    @Published var bootstrapStatus: BootstrapStatus?
    @Published var toolchainStatus: ToolchainStatus?
    @Published var appHealth: AppHealth?
    @Published var recentLogs: [LogEntry] = []
    @Published var toolchainPathInput = ""
    @Published var isRefreshing = false

    let launcherActions: [LauncherAction] = [
        LauncherAction(title: "New Profile", detail: "Starts here next."),
        LauncherAction(title: "Improve Profile", detail: "Locked into the shell."),
        LauncherAction(title: "Import Profile", detail: "Finished ICC profiles."),
        LauncherAction(title: "Import Measurements", detail: "Raw measurement evidence."),
        LauncherAction(title: "Match a Reference", detail: "Reference matching lives here next."),
        LauncherAction(title: "Verify Output", detail: "Verification surface comes next."),
        LauncherAction(title: "Recalibrate", detail: "Maintenance stays distinct."),
        LauncherAction(title: "Rebuild", detail: "Characterization rebuilds stay explicit."),
        LauncherAction(title: "Spot Measure", detail: "Spot reads will land here."),
        LauncherAction(title: "Compare Measurements", detail: "Comparison tooling comes next."),
        LauncherAction(title: "Troubleshoot", detail: "Symptom-first by default."),
        LauncherAction(title: "B&W Tuning", detail: "Monochrome workflow entry point.")
    ]

    let activeWorkItems: [ActiveWorkItem] = [
        ActiveWorkItem(title: "P900 Rag profile", nextAction: "Measure target"),
        ActiveWorkItem(title: "ET-8550 issue case", nextAction: "Review evidence"),
        ActiveWorkItem(title: "B&W wedge", nextAction: "Validate output")
    ]

    let profileHealthItems: [ProfileHealthItem] = [
        ProfileHealthItem(
            title: "P900 Rag v3",
            context: "Printer: Epson P900 | Paper: Canson Rag Photographique",
            result: "Result: avg dE00 0.9, max 2.7"
        ),
        ProfileHealthItem(
            title: "Canon Luster House Profile",
            context: "Printer & Paper Settings Unknown",
            result: "Result: not verified yet"
        )
    ]

    let storagePaths: StoragePaths

    private let bridge: EngineBridge
    private var hasBootstrapped = false

    init(storagePaths: StoragePaths = .default(), engine: EngineProtocol = Engine()) {
        self.storagePaths = storagePaths
        self.bridge = EngineBridge(engine: engine)
    }

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        await bootstrap()
    }

    func bootstrap() async {
        await runRefresh {
            let requestedPath = self.trimmedPathInput
            let status = await self.bridge.bootstrap(
                config: self.storagePaths.makeConfig(argyllOverridePath: requestedPath)
            )
            let health = await self.bridge.getAppHealth()
            let logs = await self.bridge.getRecentLogs(limit: 50)
            self.apply(status: status.toolchainStatus, bootstrapStatus: status, health: health, logs: logs)

            if requestedPath == nil {
                self.toolchainPathInput = status.toolchainStatus.resolvedInstallPath ?? ""
            }
        }
    }

    func applyToolchainPath() async {
        await runRefresh {
            let status = await self.bridge.setToolchainPath(path: self.trimmedPathInput)
            let health = await self.bridge.getAppHealth()
            let logs = await self.bridge.getRecentLogs(limit: 50)
            self.apply(
                status: status,
                bootstrapStatus: self.updatedBootstrapStatus(with: status),
                health: health,
                logs: logs
            )

            if self.trimmedPathInput == nil {
                self.toolchainPathInput = status.resolvedInstallPath ?? ""
            }
        }
    }

    func clearToolchainOverride() async {
        toolchainPathInput = ""
        await applyToolchainPath()
    }

    func revalidateToolchain() async {
        await runRefresh {
            let status = await self.bridge.setToolchainPath(path: self.trimmedPathInput)
            let health = await self.bridge.getAppHealth()
            let logs = await self.bridge.getRecentLogs(limit: 50)
            self.apply(
                status: status,
                bootstrapStatus: self.updatedBootstrapStatus(with: status),
                health: health,
                logs: logs
            )
        }
    }

    var argyllStatusLabel: String {
        switch toolchainStatus?.state {
        case .ready:
            "Ready"
        case .partial:
            "Partially Available"
        case .notFound, .none:
            "Not Found"
        }
    }

    var detectedToolchainPath: String {
        toolchainStatus?.resolvedInstallPath ?? "Not found"
    }

    var readinessLabel: String {
        switch appHealth?.readiness {
        case "ready":
            "Ready"
        case "attention":
            "Needs Attention"
        case "blocked", .none:
            "Blocked"
        default:
            appHealth?.readiness.capitalized ?? "Blocked"
        }
    }

    var lastValidationLabel: String {
        toolchainStatus?.lastValidationTime ?? "Waiting for validation"
    }

    private var trimmedPathInput: String? {
        let trimmed = toolchainPathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func updatedBootstrapStatus(with status: ToolchainStatus) -> BootstrapStatus? {
        guard let bootstrapStatus else { return nil }
        return BootstrapStatus(
            appSupportDirReady: bootstrapStatus.appSupportDirReady,
            databaseInitialized: bootstrapStatus.databaseInitialized,
            migrationsApplied: bootstrapStatus.migrationsApplied,
            toolchainStatus: status
        )
    }

    private func apply(
        status: ToolchainStatus,
        bootstrapStatus: BootstrapStatus?,
        health: AppHealth,
        logs: [LogEntry]
    ) {
        self.toolchainStatus = status
        self.bootstrapStatus = bootstrapStatus
        self.appHealth = health
        self.recentLogs = logs
    }

    private func runRefresh(_ operation: @escaping @MainActor () async -> Void) async {
        isRefreshing = true
        await operation()
        isRefreshing = false
    }
}
