import Foundation
import Testing
@testable import ArgyllUX

@MainActor
struct AppModelShellTests {
    @Test
    func launcherActionsSeparateAvailableEntriesFromPlannedWorkflows() {
        let model = makeAppModel()

        #expect(model.availableLauncherActions.map(\.title) == ["New Profile", "Troubleshoot", "Inspect", "B&W Tuning"])
        #expect(model.plannedLauncherActions.map(\.title) == [
            "Improve Profile",
            "Import Profile",
            "Import Measurements",
            "Match a Reference",
            "Verify Output",
            "Recalibrate",
            "Rebuild",
            "Spot Measure",
            "Compare Measurements",
        ])
        #expect(model.launcherActions.allSatisfy { !$0.detail.localizedCaseInsensitiveContains("comes next") })
        #expect(model.launcherActions.allSatisfy { !$0.detail.localizedCaseInsensitiveContains("locked into the shell") })
    }

    @Test
    func workflowStageDisplayLabelsHideInternalContextTerminology() {
        #expect(workflowStageDisplayTitle(.context) == "Profile Setup")
        #expect(workflowStageDisplayTitle(.target) == "Target Planning")
        #expect(workflowStageDisplayTitle(.print) == "Print Target")
        #expect(workflowStageDisplayTitle(.measure) == "Measure Target")
        #expect(workflowNextActionDisplayTitle(stage: .context, rawTitle: "Save Context") == "Continue")
    }

    @Test
    func workflowProgressItemsUseUserFacingLabels() {
        let detail = makeJobDetail(stage: .target, nextAction: "Generate Target")

        let items = workflowProgressItems(for: detail)

        #expect(items.map(\.title) == [
            "Profile Setup",
            "Target Planning",
            "Print Target",
            "Measure Target",
            "Review",
        ])
        #expect(items.first(where: { $0.stage == .target })?.state == .current)
        #expect(items.first(where: { $0.stage == .context })?.state == .completed)
    }

    @Test
    func plannedActionDescriptorMakesUnavailableStateExplicit() {
        let action = LauncherAction(
            title: "Verify Output",
            detail: "Check whether current output is still trustworthy.",
            status: "Planned",
            kind: .planned
        )

        let descriptor = action.plannedDescriptor

        #expect(descriptor?.title == "Verify Output")
        #expect(descriptor?.status == "Planned")
        #expect(descriptor?.message == "Check whether current output is still trustworthy. Not runnable in this build.")
        #expect(descriptor?.accessibilityLabel == "Verify Output. Planned. Check whether current output is still trustworthy. Not runnable in this build.")
    }

    @Test
    func jumpItemsIncludeRoutesAndLoadedRecords() async {
        let printer = makePrinter()
        let paper = makePaper()
        let profile = makePrinterProfile()
        let activeWork = makeActiveWorkItem(id: "job-1", title: "P900 Rag v1")

        let fakeEngine = FakeEngine()
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [activeWork])
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.printerProfilesCurrent = [profile]

        let model = makeAppModel(fakeEngine: fakeEngine)
        await model.bootstrapIfNeeded()

        let jumpTitles = model.shellJumpItems.map(\.title)
        #expect(jumpTitles.contains("Home"))
        #expect(jumpTitles.contains(activeWork.title))
        #expect(jumpTitles.contains(profile.name))
        #expect(jumpTitles.contains(printer.displayName))
        #expect(jumpTitles.contains(paper.displayName))

        guard let profileJump = model.shellJumpItems.first(where: { $0.destination == .printerProfile(profile.id) }) else {
            Issue.record("Expected a Printer Profile jump item.")
            return
        }
        model.openJumpItem(profileJump)

        #expect(model.selectedRoute == .printerProfiles)
        #expect(model.selectedPrinterProfileID == profile.id)

        guard let paperJump = model.shellJumpItems.first(where: { $0.destination == .settings(.paper(paper.id)) }) else {
            Issue.record("Expected a paper settings jump item.")
            return
        }
        model.openJumpItem(paperJump)

        #expect(model.selectedRoute == .settings)
        #expect(model.settings.selection == .paper(paper.id))
    }

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
