import Foundation

actor EngineBridge {
    private let engine: EngineProtocol

    init(engine: EngineProtocol = Engine()) {
        self.engine = engine
    }

    func bootstrap(config: EngineConfig) -> BootstrapStatus {
        engine.bootstrap(config: config)
    }

    func getToolchainStatus() -> ToolchainStatus {
        engine.getToolchainStatus()
    }

    func setToolchainPath(path: String?) -> ToolchainStatus {
        engine.setToolchainPath(path: path)
    }

    func getAppHealth() -> AppHealth {
        engine.getAppHealth()
    }

    func getRecentLogs(limit: UInt32) -> [LogEntry] {
        engine.getRecentLogs(limit: limit)
    }
}
