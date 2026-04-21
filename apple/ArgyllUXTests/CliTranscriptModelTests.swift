import Foundation
import Testing
@testable import ArgyllUX

@MainActor
struct CliTranscriptModelTests {
    @Test
    func openCliTranscriptKeepsExplicitJobWhenAnotherResumableJobIsNewer() async {
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
        let snapshot = makeDashboard(
            activeWorkItems: [
                makeActiveWorkItem(id: newerDetail.id, title: newerDetail.title, nextAction: newerDetail.nextAction, stage: newerDetail.stage),
                makeActiveWorkItem(id: currentDetail.id, title: currentDetail.title, nextAction: currentDetail.nextAction, stage: currentDetail.stage)
            ]
        )

        let fakeEngine = FakeEngine()
        let model = makeCliTranscriptModel(fakeEngine: fakeEngine)

        await model.openCliTranscript(
            jobId: currentDetail.id,
            activeDetail: currentDetail,
            dashboardSnapshot: snapshot
        )

        #expect(model.cliTranscriptDetail?.id == currentDetail.id)
        #expect(model.cliTranscriptTarget == .job(jobId: currentDetail.id))
    }

    @Test
    func openLatestCliTranscriptLoadsLatestResumableJobWithoutRetargetingWorkflow() async {
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
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: currentDetail.id, title: currentDetail.title)])
        fakeEngine.loadedJobDetails[currentDetail.id] = currentDetail
        fakeEngine.loadedJobDetails[newerDetail.id] = newerDetail

        let model = makeAppModel(fakeEngine: fakeEngine)
        await model.openNewProfileWorkflow()

        fakeEngine.dashboardSnapshotCurrent = makeDashboard(
            activeWorkItems: [
                makeActiveWorkItem(id: newerDetail.id, title: newerDetail.title, nextAction: newerDetail.nextAction, stage: newerDetail.stage),
                makeActiveWorkItem(id: currentDetail.id, title: currentDetail.title, nextAction: currentDetail.nextAction, stage: currentDetail.stage)
            ]
        )

        await model.openLatestCliTranscript()

        #expect(model.activeNewProfileDetail?.id == currentDetail.id)
        #expect(model.cliTranscriptDetail?.id == newerDetail.id)
        #expect(model.cliTranscriptTarget == .latestResumable(jobId: newerDetail.id))
    }

    @Test
    func openLatestCliTranscriptShowsEmptyStateWhenNoResumableJobExists() async {
        let fakeEngine = FakeEngine()
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [])
        let model = makeCliTranscriptModel(fakeEngine: fakeEngine)

        await model.openLatestCliTranscript(activeDetail: nil)

        guard case .empty = model.cliTranscriptState else {
            Issue.record("Expected the transcript window to show the empty shell-level state.")
            return
        }
    }
}
