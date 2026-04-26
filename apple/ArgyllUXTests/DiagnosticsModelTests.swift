import Foundation
import Testing
@testable import ArgyllUX

@MainActor
struct DiagnosticsModelTests {
    @Test
    func refreshLoadsSummaryAndEvents() async {
        let fakeEngine = FakeEngine()
        fakeEngine.diagnosticsSummaryValue = makeDiagnosticsSummary(total: 3, warnings: 1, errors: 1, critical: 0)
        fakeEngine.diagnosticEventsValue = [
            makeDiagnosticEvent(level: .info, category: .app, message: "Bootstrap complete."),
            makeDiagnosticEvent(level: .warning, category: .toolchain, message: "Toolchain partial."),
            makeDiagnosticEvent(level: .error, category: .database, message: "Database write failed."),
        ]
        let model = DiagnosticsModel(bridge: EngineBridge(engine: fakeEngine))

        await model.refresh()

        #expect(model.summary?.totalCount == 3)
        #expect(model.visibleEvents.map(\.message) == [
            "Bootstrap complete.",
            "Toolchain partial.",
            "Database write failed.",
        ])
        #expect(model.isLoading == false)
    }

    @Test
    func errorsOnlyFilterRequestsErrorAndCriticalEvents() async {
        let fakeEngine = FakeEngine()
        let model = DiagnosticsModel(bridge: EngineBridge(engine: fakeEngine))

        model.errorsOnly = true
        await model.refresh()

        #expect(fakeEngine.lastDiagnosticFilter?.errorsOnly == true)
        #expect(fakeEngine.lastDiagnosticFilter?.limit == 200)
    }

    @Test
    func commandLinkedEventRequestsTranscriptForRelatedJob() {
        let model = DiagnosticsModel(bridge: EngineBridge(engine: FakeEngine()))
        var openedJobID: String?
        model.openCliTranscriptRequested = { openedJobID = $0 }

        model.openCliTranscript(for: makeDiagnosticEvent(
            level: .error,
            category: .cli,
            message: "colprof failed.",
            jobId: "job-1",
            commandId: "command-1"
        ))

        #expect(openedJobID == "job-1")
    }
}
