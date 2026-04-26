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
    func olderRefreshCannotOverwriteNewerResults() async {
        let fakeEngine = FakeEngine()
        let olderEvent = makeDiagnosticEvent(message: "Older diagnostic.")
        let newerEvent = makeDiagnosticEvent(message: "Newer diagnostic.")
        fakeEngine.diagnosticsSummaryValue = makeDiagnosticsSummary(total: 1, warnings: 1)
        fakeEngine.diagnosticEventsValue = [olderEvent]
        let model = DiagnosticsModel(bridge: EngineBridge(engine: fakeEngine))
        let hold = FirstRefreshHold()
        model.refreshResultsReadyForTesting = {
            await hold.holdFirstRefresh()
        }

        let firstRefresh = Task {
            await model.refresh()
        }
        await hold.waitUntilHeld()

        fakeEngine.diagnosticsSummaryValue = makeDiagnosticsSummary(total: 2, warnings: 0, errors: 1)
        fakeEngine.diagnosticEventsValue = [newerEvent]
        await model.refresh()

        #expect(model.summary?.totalCount == 2)
        #expect(model.visibleEvents.map(\.message) == ["Newer diagnostic."])
        #expect(model.selectedEventID == newerEvent.id)
        #expect(model.isLoading == false)

        hold.release()
        await firstRefresh.value

        #expect(model.summary?.totalCount == 2)
        #expect(model.visibleEvents.map(\.message) == ["Newer diagnostic."])
        #expect(model.selectedEventID == newerEvent.id)
        #expect(model.isLoading == false)
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

@MainActor
private final class FirstRefreshHold {
    private var didHold = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func holdFirstRefresh() async {
        guard didHold == false else { return }

        didHold = true
        enteredContinuation?.resume()
        enteredContinuation = nil

        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilHeld() async {
        guard didHold == false else { return }

        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
