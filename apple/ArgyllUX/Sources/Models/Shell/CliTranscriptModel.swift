import Foundation

enum CliTranscriptTarget: Equatable {
    case latestResumable(jobId: String?)
    case job(jobId: String)

    var resolvedJobId: String? {
        switch self {
        case let .latestResumable(jobId):
            return jobId
        case let .job(jobId):
            return jobId
        }
    }
}

// Transcript state stays separate from workflow selection so shell-level
// transcript browsing cannot silently retarget the active job detail.
enum CliTranscriptState {
    case empty
    case loading
    case deleted(jobTitle: String?)
    case loaded(NewProfileJobDetail)

    var detail: NewProfileJobDetail? {
        guard case let .loaded(detail) = self else { return nil }
        return detail
    }
}

/// Owns transcript targeting and polling so shell/window rules stay isolated
/// from the New Profile editor state machine.
@MainActor
final class CliTranscriptModel: ObservableObject {
    @Published private(set) var cliTranscriptTarget: CliTranscriptTarget?
    @Published private(set) var cliTranscriptState: CliTranscriptState = .empty

    private let bridge: EngineBridge
    private let fileOpener: FileOpening
    private var cliTranscriptPollTask: Task<Void, Never>?

    var dashboardDidChange: ((DashboardSnapshot) -> Void)?
    var showJobRequested: ((String) -> Void)?

    init(bridge: EngineBridge, fileOpener: FileOpening) {
        self.bridge = bridge
        self.fileOpener = fileOpener
    }

    var cliTranscriptDetail: NewProfileJobDetail? {
        cliTranscriptState.detail
    }

    func openCliTranscript(jobId: String, activeDetail: NewProfileJobDetail?, dashboardSnapshot: DashboardSnapshot?) async {
        let target = CliTranscriptTarget.job(jobId: jobId)
        let preferredDetail: NewProfileJobDetail?
        if activeDetail?.id == jobId {
            preferredDetail = activeDetail
        } else if cliTranscriptDetail?.id == jobId {
            preferredDetail = cliTranscriptDetail
        } else {
            preferredDetail = nil
        }

        if let preferredDetail {
            cliTranscriptTarget = target
            applyCliTranscriptDetail(preferredDetail, requestedJobId: jobId, snapshot: dashboardSnapshot)
            return
        }

        setCliTranscriptLoading(target: target)
        await loadCliTranscriptDetail(jobId: jobId, snapshot: nil)
    }

    func openLatestCliTranscript(activeDetail: NewProfileJobDetail?) async {
        setCliTranscriptLoading(target: .latestResumable(jobId: nil))

        let snapshot = await bridge.getDashboardSnapshot()
        dashboardDidChange?(snapshot)

        guard let jobId = latestResumableNewProfileJobID(from: snapshot) else {
            setCliTranscriptEmpty(target: .latestResumable(jobId: nil))
            return
        }

        cliTranscriptTarget = .latestResumable(jobId: jobId)

        if activeDetail?.id == jobId, let detail = activeDetail {
            applyCliTranscriptDetail(detail, requestedJobId: jobId, snapshot: snapshot)
            return
        }

        if cliTranscriptDetail?.id == jobId, let detail = cliTranscriptDetail {
            applyCliTranscriptDetail(detail, requestedJobId: jobId, snapshot: snapshot)
            return
        }

        await loadCliTranscriptDetail(jobId: jobId, snapshot: snapshot)
    }

    func reloadTranscriptIfTracking(jobId: String, snapshot: DashboardSnapshot?) async {
        guard cliTranscriptTarget?.resolvedJobId == jobId || cliTranscriptDetail?.id == jobId else { return }
        await loadCliTranscriptDetail(jobId: jobId, snapshot: snapshot)
    }

    func setDeleted(jobTitle: String?) {
        setCliTranscriptDeleted(jobTitle: jobTitle)
    }

    func openOutputFolder(_ path: String) {
        fileOpener.revealPathInFinder(path)
    }

    func showJob(_ jobId: String) {
        showJobRequested?(jobId)
    }

    private func loadCliTranscriptDetail(jobId: String, snapshot: DashboardSnapshot?) async {
        let detail = await bridge.getNewProfileJobDetail(jobId: jobId)
        let resolvedSnapshot: DashboardSnapshot

        if let snapshot {
            resolvedSnapshot = snapshot
        } else {
            resolvedSnapshot = await bridge.getDashboardSnapshot()
            dashboardDidChange?(resolvedSnapshot)
        }

        guard cliTranscriptTarget?.resolvedJobId == jobId else { return }
        applyCliTranscriptDetail(detail, requestedJobId: jobId, snapshot: resolvedSnapshot)
    }

    private func applyCliTranscriptDetail(
        _ detail: NewProfileJobDetail,
        requestedJobId: String,
        snapshot: DashboardSnapshot?
    ) {
        guard cliTranscriptTarget?.resolvedJobId == requestedJobId else { return }

        if let snapshot, isMissingCliTranscriptDetail(detail, requestedJobId: requestedJobId, snapshot: snapshot) {
            setCliTranscriptDeleted(jobTitle: nil)
            return
        }

        cliTranscriptState = .loaded(detail)

        if detail.isCommandRunning {
            startCliTranscriptPollingIfNeeded()
        } else {
            stopCliTranscriptPolling()
        }
    }

    private func latestResumableNewProfileJobID(from snapshot: DashboardSnapshot) -> String? {
        snapshot.activeWorkItems.first { $0.kind == "new_profile" }?.id
    }

    private func isMissingCliTranscriptDetail(
        _ detail: NewProfileJobDetail,
        requestedJobId: String,
        snapshot: DashboardSnapshot
    ) -> Bool {
        guard detail.id == requestedJobId else { return false }
        guard !snapshot.activeWorkItems.contains(where: { $0.id == requestedJobId }) else { return false }
        guard detail.stage == .failed else { return false }

        return detail.workspacePath.isEmpty &&
            detail.profileName.isEmpty &&
            detail.printer == nil &&
            detail.paper == nil &&
            detail.commands.isEmpty
    }

    private func startCliTranscriptPollingIfNeeded() {
        stopCliTranscriptPolling()

        guard let detail = cliTranscriptDetail, detail.isCommandRunning else { return }

        cliTranscriptPollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)

                guard let currentJobId = await MainActor.run(body: { self.cliTranscriptTarget?.resolvedJobId }) else {
                    return
                }

                let detail = await self.bridge.getNewProfileJobDetail(jobId: currentJobId)
                let snapshot = await self.bridge.getDashboardSnapshot()

                await MainActor.run {
                    self.dashboardDidChange?(snapshot)
                    self.applyCliTranscriptDetail(detail, requestedJobId: currentJobId, snapshot: snapshot)
                }

                if !detail.isCommandRunning {
                    return
                }
            }
        }
    }

    private func stopCliTranscriptPolling() {
        cliTranscriptPollTask?.cancel()
        cliTranscriptPollTask = nil
    }

    private func setCliTranscriptLoading(target: CliTranscriptTarget) {
        cliTranscriptTarget = target
        stopCliTranscriptPolling()
        cliTranscriptState = .loading
    }

    private func setCliTranscriptEmpty(target: CliTranscriptTarget?) {
        cliTranscriptTarget = target
        stopCliTranscriptPolling()
        cliTranscriptState = .empty
    }

    private func setCliTranscriptDeleted(jobTitle: String?) {
        stopCliTranscriptPolling()
        cliTranscriptState = .deleted(jobTitle: jobTitle)
    }
}
