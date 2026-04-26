import Foundation
import Testing
@testable import ArgyllUX

@MainActor
struct ProfileLibraryModelTests {
    @Test
    func applyProfilesFallsBackToFirstAvailableSelection() {
        let first = makePrinterProfile()
        let second = makeAlternatePrinterProfile()
        let model = ProfileLibraryModel()

        model.selectProfile(id: second.id)
        model.applyProfiles([first])

        #expect(model.selectedPrinterProfileID == first.id)
        #expect(model.selectedPrinterProfile?.id == first.id)
    }

    @Test
    func publishProfileRefreshesLibrarySelection() async {
        let printer = makePrinter()
        let paper = makePaper()
        let review = ReviewSummaryRecord(
            result: "Pass",
            verifiedAgainstFile: "/tmp/job-1/profile.icc",
            printSettings: "Premium Luster / 1440 dpi",
            lastVerificationDate: "2026-04-19T18:50:00Z",
            averageDe00: 1.2,
            maximumDe00: 2.8,
            notes: "Good first build."
        )
        let reviewDetail = makeJobDetail(
            stage: .review,
            nextAction: "Publish",
            printer: printer,
            paper: paper,
            review: review
        )
        let publishedDetail = makeJobDetail(
            stage: .completed,
            nextAction: "Open in Printer Profiles",
            printer: printer,
            paper: paper,
            review: review,
            publishedProfileId: "profile-1"
        )
        let publishedProfile = makePrinterProfile()

        let fakeEngine = FakeEngine()
        fakeEngine.appHealthValue = AppHealth(readiness: "ready", blockingIssues: [], warnings: [])
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: reviewDetail.id)])
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.createNewProfileDraftResult = reviewDetail
        fakeEngine.publishNewProfileResult = publishedDetail
        fakeEngine.printerProfilesCurrent = []
        fakeEngine.printerProfilesAfterPublish = [publishedProfile]

        let model = makeAppModel(fakeEngine: fakeEngine)
        await model.openNewProfileWorkflow()
        await model.publishProfile()

        #expect(fakeEngine.lastPublishedJobId == reviewDetail.id)
        #expect(model.activeNewProfileDetail?.publishedProfileId == "profile-1")
        #expect(model.printerProfiles.map(\.id) == ["profile-1"])
        #expect(model.selectedPrinterProfileID == "profile-1")
    }

    @Test
    func confirmPrinterProfileDeletionReopensSourceJobForReview() async {
        let printer = makePrinter()
        let paper = makePaper()
        let review = ReviewSummaryRecord(
            result: "Pass",
            verifiedAgainstFile: "/tmp/job-1/profile.icc",
            printSettings: "Premium Luster / 1440 dpi",
            lastVerificationDate: "2026-04-19T18:50:00Z",
            averageDe00: 1.2,
            maximumDe00: 2.8,
            notes: "Good first build."
        )
        let publishedDetail = makeJobDetail(
            stage: .completed,
            nextAction: "Open in Printer Profiles",
            printer: printer,
            paper: paper,
            review: review,
            publishedProfileId: "profile-1"
        )
        let reopenedDetail = makeJobDetail(
            stage: .review,
            nextAction: "Publish",
            printer: printer,
            paper: paper,
            review: review
        )
        let publishedProfile = makePrinterProfile()

        let fakeEngine = FakeEngine()
        fakeEngine.appHealthValue = AppHealth(readiness: "ready", blockingIssues: [], warnings: [])
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [])
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.printerProfilesCurrent = [publishedProfile]
        fakeEngine.createNewProfileDraftResult = publishedDetail
        fakeEngine.loadedJobDetails[publishedDetail.id] = publishedDetail
        fakeEngine.deletePrinterProfileResult = DeleteResult(success: true, message: "")
        fakeEngine.jobDetailAfterDeletePrinterProfile = reopenedDetail
        fakeEngine.dashboardSnapshotAfterDeletePrinterProfile = makeDashboard(
            activeWorkItems: [
                makeActiveWorkItem(
                    id: reopenedDetail.id,
                    title: reopenedDetail.title,
                    nextAction: reopenedDetail.nextAction,
                    stage: reopenedDetail.stage
                )
            ]
        )

        let model = makeAppModel(fakeEngine: fakeEngine)
        await model.openNewProfileWorkflow()
        model.requestCurrentWorkflowDeletion()
        let deletionTask = model.confirmPendingDeletion()
        await deletionTask?.value

        #expect(fakeEngine.lastDeletedProfileId == "profile-1")
        #expect(model.activeNewProfileDetail?.stage == .review)
        #expect(model.activeNewProfileDetail?.publishedProfileId == nil)
        #expect(model.printerProfiles.isEmpty)
        #expect(model.activeWorkItems.map(\.id) == [reopenedDetail.id])
        #expect(model.deletionErrorMessage == nil)
    }
}
