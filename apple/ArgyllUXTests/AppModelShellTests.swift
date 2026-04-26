import Foundation
import Testing
@testable import ArgyllUX

@MainActor
struct AppModelShellTests {
    @Test
    func bootstrapLoadsToolchainHealthAndDashboardSnapshot() async {
        let root = makeTemporaryRoot()
        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.bootstrapStatusValue = BootstrapStatus(
            appSupportDirReady: true,
            databaseInitialized: true,
            migrationsApplied: true,
            toolchainStatus: fakeEngine.toolchainStatusValue
        )
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [])
        fakeEngine.appHealthValue = AppHealth(
            readiness: "ready",
            blockingIssues: [],
            warnings: ["Storage location: /tmp/ArgyllUX"]
        )
        fakeEngine.logsValue = [
            LogEntry(
                timestamp: "2026-04-19T18:30:00Z",
                level: "info",
                message: "Bootstrap completed.",
                source: "engine.bootstrap"
            )
        ]

        let model = makeAppModel(root: root, fakeEngine: fakeEngine)
        await model.bootstrapIfNeeded()

        #expect(fakeEngine.bootstrapCallCount == 1)
        #expect(model.toolchainStatus?.state == .ready)
        #expect(model.toolchainStatus?.argyllVersion == "3.5.0")
        #expect(model.appHealth?.readiness == "ready")
        #expect(model.jobsCount == 0)
        #expect(model.detectedToolchainPath == "/opt/homebrew/bin")
        #expect(model.recentLogs.isEmpty)
        #expect(model.toolchainPathInput == "/opt/homebrew/bin")
    }

    @Test
    func diagnosticsModelRefreshesThroughAppModel() async {
        let fakeEngine = FakeEngine()
        fakeEngine.diagnosticsSummaryValue = makeDiagnosticsSummary(total: 1)
        fakeEngine.diagnosticEventsValue = [
            makeDiagnosticEvent(level: .info, category: .environment, message: "Bootstrap environment captured.")
        ]

        let model = makeAppModel(fakeEngine: fakeEngine)
        await model.diagnostics.refresh()

        #expect(model.diagnostics.summary?.totalCount == 1)
        #expect(model.diagnostics.visibleEvents.first?.message == "Bootstrap environment captured.")
    }

    @Test
    func confirmActiveWorkDeletionClearsDeletedJob() async {
        let draftDetail = makeJobDetail(stage: .context, nextAction: "Save Context")
        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.loadedJobDetails[draftDetail.id] = draftDetail
        fakeEngine.deleteNewProfileJobResult = DeleteResult(success: true, message: "")

        let model = makeAppModel(fakeEngine: fakeEngine)
        await model.openNewProfileWorkflow()
        await model.openCliTranscript(jobId: draftDetail.id)
        model.requestActiveWorkDeletion(makeActiveWorkItem(id: draftDetail.id))
        let deletionTask = model.confirmPendingDeletion()
        await deletionTask?.value

        #expect(fakeEngine.lastDeletedJobId == draftDetail.id)
        #expect(model.activeNewProfileDetail == nil)
        #expect(model.activeWorkItems.isEmpty)
        #expect(model.deletionErrorMessage == nil)

        guard case let .deleted(jobTitle) = model.cliTranscriptState else {
            Issue.record("Expected the transcript window to move into the deleted-job state.")
            return
        }

        #expect(jobTitle == draftDetail.title)
        #expect(model.cliTranscriptTarget == .job(jobId: draftDetail.id))
    }

    @Test
    func confirmActiveWorkDeletionKeepsShellTranscriptTargetAfterFooterSelection() async {
        let currentDetail = makeJobDetail(
            id: "job-1",
            title: "P900 Rag v1",
            stage: .context,
            nextAction: "Save Context"
        )
        let newerDetail = makeJobDetail(
            id: "job-2",
            title: "P900 Rag v2",
            stage: .target,
            nextAction: "Generate Target"
        )

        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(
            activeWorkItems: [
                makeActiveWorkItem(id: newerDetail.id, title: newerDetail.title, nextAction: newerDetail.nextAction, stage: newerDetail.stage),
                makeActiveWorkItem(id: currentDetail.id, title: currentDetail.title, nextAction: currentDetail.nextAction, stage: currentDetail.stage)
            ]
        )
        fakeEngine.loadedJobDetails[currentDetail.id] = currentDetail
        fakeEngine.loadedJobDetails[newerDetail.id] = newerDetail

        let model = makeAppModel(fakeEngine: fakeEngine)
        await model.openLatestCliTranscript()
        model.requestActiveWorkDeletion(makeActiveWorkItem(id: newerDetail.id, title: newerDetail.title, nextAction: newerDetail.nextAction, stage: newerDetail.stage))
        let deletionTask = model.confirmPendingDeletion()
        await deletionTask?.value

        guard case let .deleted(jobTitle) = model.cliTranscriptState else {
            Issue.record("Expected the transcript window to move into the deleted-job state.")
            return
        }

        #expect(jobTitle == newerDetail.title)
        #expect(model.cliTranscriptTarget == .latestResumable(jobId: newerDetail.id))
    }

    @Test
    func confirmActiveWorkDeletionFailureKeepsLoadedJobAndShowsError() async {
        let draftDetail = makeJobDetail(stage: .context, nextAction: "Save Context")
        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.loadedJobDetails[draftDetail.id] = draftDetail
        fakeEngine.deleteNewProfileJobResult = DeleteResult(success: false, message: "Database is locked.")

        let model = makeAppModel(fakeEngine: fakeEngine)
        await model.openNewProfileWorkflow()
        model.requestActiveWorkDeletion(makeActiveWorkItem(id: draftDetail.id))
        let deletionTask = model.confirmPendingDeletion()
        await deletionTask?.value

        #expect(model.activeNewProfileDetail?.id == draftDetail.id)
        #expect(model.activeWorkItems.map(\.id) == [draftDetail.id])
        #expect(model.deletionErrorMessage == "Database is locked.")
    }

    @Test
    func genericNewProfileDeletionConfirmationIncludesJobId() {
        let model = makeAppModel()

        model.requestActiveWorkDeletion(jobId: "job-blank-1", title: "New Profile")

        #expect(model.deletionConfirmationMessage == "This removes New Profile (job-blank-1) and its unpublished working files.")
    }

    @Test
    func confirmCurrentWorkflowDeletionUsesActiveWorkPathForGenericDraft() async {
        let draftDetail = makeJobDetail(
            id: "job-blank-1",
            title: "New Profile",
            stage: .context,
            nextAction: "Save Context"
        )
        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(
            activeWorkItems: [
                makeActiveWorkItem(
                    id: draftDetail.id,
                    title: draftDetail.title,
                    nextAction: draftDetail.nextAction,
                    stage: draftDetail.stage
                )
            ]
        )
        fakeEngine.loadedJobDetails[draftDetail.id] = draftDetail
        fakeEngine.deleteNewProfileJobResult = DeleteResult(success: true, message: "")

        let model = makeAppModel(fakeEngine: fakeEngine)
        await model.openNewProfileWorkflow()
        model.requestCurrentWorkflowDeletion()

        #expect(model.deletionConfirmationMessage == "This removes New Profile (job-blank-1) and its unpublished working files.")

        let deletionTask = model.confirmPendingDeletion()
        await deletionTask?.value

        #expect(fakeEngine.lastDeletedJobId == draftDetail.id)
        #expect(model.activeNewProfileDetail == nil)
        #expect(model.activeWorkflow == nil)
        #expect(model.activeWorkItems.isEmpty)
    }

    @Test
    func confirmedDeletionSurvivesDialogDismissalClearingPresentationBinding() async {
        let draftDetail = makeJobDetail(
            id: "job-blank-1",
            title: "New Profile",
            stage: .context,
            nextAction: "Save Context"
        )
        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(
            activeWorkItems: [
                makeActiveWorkItem(
                    id: draftDetail.id,
                    title: draftDetail.title,
                    nextAction: draftDetail.nextAction,
                    stage: draftDetail.stage
                )
            ]
        )
        fakeEngine.loadedJobDetails[draftDetail.id] = draftDetail
        fakeEngine.deleteNewProfileJobResult = DeleteResult(success: true, message: "")

        let model = makeAppModel(fakeEngine: fakeEngine)
        await model.openNewProfileWorkflow()
        model.requestCurrentWorkflowDeletion()

        let deletionTask = model.confirmPendingDeletion()
        model.cancelPendingDeletion()
        await deletionTask?.value

        #expect(fakeEngine.lastDeletedJobId == draftDetail.id)
        #expect(model.activeNewProfileDetail == nil)
        #expect(model.activeWorkflow == nil)
        #expect(model.activeWorkItems.isEmpty)
    }
}
