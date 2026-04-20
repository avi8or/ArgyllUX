import SwiftUI

struct CliTranscriptWindowView: View {
    static let windowID = "cli-transcript"

    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            switch model.cliTranscriptState {
            case .empty:
                transcriptPlaceholder(
                    title: "CLI Transcript",
                    message: emptyTranscriptMessage,
                    secondaryMessage: emptyTranscriptSecondaryMessage
                )
            case .loading:
                transcriptPlaceholder(
                    title: "CLI Transcript",
                    message: loadingTranscriptMessage,
                    secondaryMessage: loadingTranscriptSecondaryMessage
                )
            case let .deleted(jobTitle):
                transcriptPlaceholder(
                    title: "CLI Transcript",
                    message: deletedTranscriptMessage(jobTitle: jobTitle),
                    secondaryMessage: deletedTranscriptSecondaryMessage
                )
            case let .loaded(detail):
                VStack(alignment: .leading, spacing: 16) {
                    header(detail)

                    if let latestError = detail.latestError,
                       detail.stage == .blocked || detail.stage == .failed {
                        Text(latestError)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }

                    if detail.commands.isEmpty {
                        emptyTranscriptState
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(detail.commands, id: \.id) { command in
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                                            Text(command.label)
                                                .font(.headline)

                                            Spacer()

                                            Text(commandSummary(command))
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }

                                        Text(command.argv.joined(separator: " "))
                                            .font(.system(.footnote, design: .monospaced))
                                            .textSelection(.enabled)

                                        if command.events.isEmpty {
                                            Text("Waiting for output.")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            ForEach(command.events, id: \.id) { event in
                                                HStack(alignment: .top, spacing: 8) {
                                                    Text(streamLabel(event.stream))
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(event.stream == .stderr ? Color.red : Color.secondary)
                                                        .frame(width: 42, alignment: .leading)

                                                    Text(event.message)
                                                        .font(.system(.footnote, design: .monospaced))
                                                        .foregroundStyle(event.stream == .stderr ? Color.red : Color.primary)
                                                        .textSelection(.enabled)
                                                }
                                            }
                                        }
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 820, minHeight: 420, alignment: .topLeading)
    }

    private func header(_ detail: NewProfileJobDetail) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("CLI Transcript")
                    .font(.title2.weight(.semibold))

                Text(detail.title)
                    .font(.headline)

                HStack(spacing: 10) {
                    Text(stageTitle(detail.stage))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(detail.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if detail.isCommandRunning {
                        Text("Live")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Job ID: \(detail.id)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Button("Show Job") {
                    model.openNewProfileJob(jobId: detail.id)
                }

                Button("Open Output Folder") {
                    model.revealPathInFinder(detail.workspacePath)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyTranscriptState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No Argyll commands have run for this job yet.")
                .font(.subheadline)
            Text("Argyll command output appears here after the first command starts. Bootstrap and toolchain logs are not shown in this window.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func transcriptPlaceholder(
        title: String,
        message: String,
        secondaryMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.subheadline)
            Text(secondaryMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func deletedTranscriptMessage(jobTitle: String?) -> String {
        guard let jobTitle, !jobTitle.isEmpty else {
            return "This New Profile job was deleted."
        }

        return "\"\(jobTitle)\" was deleted."
    }

    private var emptyTranscriptMessage: String {
        switch model.cliTranscriptTarget {
        case .latestResumable(jobId: _):
            return "No active New Profile work is ready to inspect."
        case .job(jobId: _):
            return "Open CLI Transcript from a New Profile job to inspect that job's Argyll command output."
        case nil:
            return "Open CLI Transcript from a New Profile job to inspect that job's Argyll command output."
        }
    }

    private var emptyTranscriptSecondaryMessage: String {
        switch model.cliTranscriptTarget {
        case .latestResumable(jobId: _):
            return "Start or resume New Profile from Home, Active work, or Settings, then choose CLI Transcript again from the footer."
        case .job(jobId: _):
            return "Argyll command output appears here after that job starts running commands."
        case nil:
            return "The footer button loads the latest resumable New Profile job when one exists."
        }
    }

    private var loadingTranscriptMessage: String {
        switch model.cliTranscriptTarget {
        case .latestResumable(jobId: _):
            return "Loading the latest resumable New Profile transcript."
        case .job(jobId: _):
            return "Loading transcript output for the selected New Profile job."
        case nil:
            return "Loading transcript output."
        }
    }

    private var loadingTranscriptSecondaryMessage: String {
        switch model.cliTranscriptTarget {
        case .latestResumable(jobId: _):
            return "Argyll command output appears here for the job the footer just resolved."
        case .job(jobId: _):
            return "Argyll command output appears here for the selected New Profile job."
        case nil:
            return "Argyll command output appears here for the selected New Profile job."
        }
    }

    private var deletedTranscriptSecondaryMessage: String {
        switch model.cliTranscriptTarget {
        case .latestResumable(jobId: _):
            return "Choose CLI Transcript again from the footer to load the latest resumable New Profile job."
        case .job(jobId: _):
            return "Open New Profile again from Home, Active work, or Printer Profiles to keep working."
        case nil:
            return "Choose CLI Transcript again after you open another New Profile job."
        }
    }

    private func commandSummary(_ command: JobCommandRecord) -> String {
        switch command.state {
        case .running:
            return "Running"
        case .succeeded:
            return "Succeeded"
        case .failed:
            if let exitCode = command.exitCode {
                return "Failed (\(exitCode))"
            }
            return "Failed"
        }
    }

    private func stageTitle(_ stage: WorkflowStage) -> String {
        switch stage {
        case .context:
            "Context"
        case .target:
            "Target"
        case .print:
            "Print"
        case .drying:
            "Drying"
        case .measure:
            "Measure"
        case .build:
            "Build"
        case .review:
            "Review"
        case .publish:
            "Publish"
        case .completed:
            "Completed"
        case .blocked:
            "Blocked"
        case .failed:
            "Failed"
        }
    }

    private func streamLabel(_ stream: CommandStream) -> String {
        switch stream {
        case .stdout:
            "stdout"
        case .stderr:
            "stderr"
        case .system:
            "system"
        }
    }
}
