# Diagnostics System Design

**Date:** 2026-04-26
**Status:** Approved design, pending written-spec review
**Scope:** CLI transcript integration, app diagnostics, error diagnostics, performance timing, production-safe export, and future enforcement.

## Purpose

ArgyllUX needs a diagnostics system that helps development now and remains useful in production for an open-source desktop app. The current app has two useful but narrow surfaces:

- The CLI Transcript is job-scoped and command-focused.
- The Error Log Viewer filters recent engine log entries to errors.

The next step is to keep the CLI Transcript as the authoritative command-output surface while replacing the narrow Error Log Viewer with a broader Diagnostics surface. Diagnostics should record normal operation, warnings, errors, performance timings, environment context, and privacy-safe issue-report data.

## Goals

- Capture normal operation, not only hard failures, because non-blocking behavior can reveal performance and workflow problems.
- Keep diagnostics always on in production with bounded local retention.
- Avoid collecting private user data in the global diagnostics stream.
- Make issue reports easier by exporting a redacted diagnostics bundle.
- Preserve the existing job-scoped CLI Transcript for full command inspection.
- Make future features explicitly account for diagnostics, privacy, and observability.

## Non-Goals

- Do not replace the CLI Transcript with a generic log console.
- Do not duplicate full stdout, stderr, file contents, profile bytes, measurement contents, or user notes into global diagnostics.
- Do not build a full observability platform before the core profiling workflows mature.
- Do not move durable diagnostics persistence into SwiftData, Core Data, or ad hoc Swift-owned files.

## Architecture

Diagnostics uses two related but distinct surfaces.

The **CLI Transcript** remains job-scoped and command-focused. It continues to own full Argyll command output, argv, stdout, stderr, system messages, command state, and exit code.

The **Diagnostics** surface becomes the global investigation tool. It records app, UI, engine, CLI summary, database, toolchain, workflow, performance, and environment events in a structured Rust-owned store.

Ownership follows the repo boundary:

- Rust owns durable diagnostics persistence, retention, export assembly, engine events, CLI summary events, toolchain events, database events, workflow events, and sanitization rules.
- Swift owns presentation and app/UI event emission. Swift emits structured diagnostics through coarse bridge methods instead of writing its own diagnostics store.
- The bridge stays coarse. Expected methods include `recordDiagnosticEvent`, `listDiagnosticEvents`, `getDiagnosticsSummary`, `exportDiagnosticsBundle`, and retention/config methods if needed.

Diagnostics links to command transcripts through stable IDs. A diagnostics event can show that `Generate Target` failed or that `Build Profile` took 42 seconds, then open the full CLI Transcript for the related job.

## Event Model

Diagnostics should use structured events as the source of truth, not free-form log lines.

Core fields:

- `id`
- `timestamp`
- `level`: `debug`, `info`, `warning`, `error`, `critical`
- `category`: `app`, `ui`, `workflow`, `engine`, `cli`, `database`, `toolchain`, `performance`, `environment`
- `source`: stable source string such as `swift.workflow.new_profile` or `engine.cli`
- `message`: short human-readable summary
- `details`: structured JSON payload after sanitization
- `privacy`: `public`, `internal`, or `sensitive_redacted`
- `job_id`, `command_id`, `profile_id`, `issue_case_id`: optional correlation fields
- `duration_ms`: optional timing field
- `operation_id` and `parent_operation_id`: optional span correlation fields

First-class event types:

- App bootstrap and readiness changes
- Swift UI actions that start durable work
- Bridge calls that mutate state or trigger expensive work
- Rust workflow transitions
- Argyll command start and finish summaries
- Toolchain discovery and override changes
- Database migration and persistence failures
- Performance spans for bootstrap, refresh, bridge calls, command phases, and database operations
- Environment snapshot on bootstrap and export

The existing newline-delimited `engine.log` can remain during transition as a compatibility/debug artifact. The SQLite diagnostics table becomes the durable source of truth for the new Diagnostics surface.

## Privacy Rules

The global diagnostics stream must not collect private user data. This is a hard design constraint, not an export-only cleanup step.

Never record:

- File contents
- Measurement contents
- ICC/profile bytes
- CGATS rows
- User notes
- Arbitrary command stdout/stderr payloads
- Hostnames
- Usernames
- Serial numbers
- Network information
- Device identifiers
- Full filesystem inventories

Avoid recording user-entered names by default:

- Printer names
- Paper names
- Profile names
- Issue Case titles
- Free-form notes

Diagnostics should use stable local IDs and redacted labels instead of user-entered names. When a human-readable label is needed, use a safe generic label such as `Printer Profile`, `Paper`, `Job`, or `Issue Case`.

Path handling:

- Global diagnostic events should not persist full user home paths.
- Local UI can show known app paths from the current app model when the user is inspecting their own machine, but those paths should not be copied into diagnostic event payloads.
- Export must redact paths to safe forms such as `$APP_SUPPORT/...`, `$LOGS/...`, `$JOB_WORKSPACE/...`, or filename-only values where appropriate.

Command handling:

- Diagnostics may record command kind, stage, start/finish status, sanitized argument shape, duration, exit code, and related IDs.
- Diagnostics must not record raw arbitrary stdout/stderr.
- CLI Transcript remains the local job-specific surface for full command output.
- Export includes full CLI transcripts only when the user explicitly opts in.

Environment snapshots must be coarse:

- App version
- macOS version
- CPU architecture
- Argyll version
- Resolved Argyll path category, not full private path when exported
- Database schema version
- Feature/config flags that are not private

## Retention

Diagnostics are always on, but bounded.

Default retention is based on both time and size. The first implementation should use:

- Last 30 days
- 50 MB maximum diagnostics storage size
- 64 KB maximum structured payload size per event after sanitization

Retention pruning should run during bootstrap and after large writes. Pruning failures should themselves produce diagnostic events with sanitized details.

Full CLI transcript output follows job lifecycle rules and is not duplicated into the global diagnostics event list.

## Diagnostics UI

The footer action should become **Diagnostics** instead of **Error Log Viewer**.

The Diagnostics UI should make errors easy to find without making errors the only useful data.

Proposed layout:

- Summary strip: event totals, warning/error counts, latest critical issue, app readiness, current Argyll version/path category, and retention status
- Filter bar: level, category, time range, job/profile correlation, text search, and `Errors Only`
- Event list: timestamp, level, category, source, message, and duration when present
- Detail pane: structured details, related job/profile/command links, copy event, and safe path reveal actions where appropriate
- Environment view: app version, macOS version, Argyll version/path category, database/log storage category, and build/config facts
- Export action: creates a redacted diagnostics bundle suitable for GitHub issues

State handling:

- Empty state says diagnostics are recording and explains where safe data lives.
- Loading state shows visible refresh/progress.
- Export and retention failures appear as diagnostic events.
- Large event sets remain bounded, filterable, and not rendered as one unbounded SwiftUI list.

CLI integration:

- Diagnostics shows command start/finish summaries and failed command events.
- Selecting a command-linked event can open the CLI Transcript for the related job.
- Full stdout/stderr stays in the CLI Transcript and optional export evidence.

## Export Bundle

Export should be redacted by default and suitable for GitHub issue reports.

Expected contents:

- `diagnostics.jsonl` or `diagnostics.json`
- `environment.json`
- selected job summaries
- selected CLI transcripts only when explicitly included
- app health and toolchain status
- retention/export metadata
- a README-style issue-report note explaining what is included and what was redacted

Export must default to privacy-preserving output. Including full CLI transcripts or local paths requires an explicit user action with clear wording.

## Enforcement

Diagnostics upkeep should be part of the project process.

Required project/process changes:

- Update `AGENTS.md` and `CLAUDE.md` in the implementation phase with the same diagnostics requirement.
- Add a plan/spec template section named `Diagnostics, Privacy, And Observability`.
- Add a lightweight repo script under `scripts/` that checks changed plan/spec docs for the diagnostics section when relevant.
- Add code review guidance that same-class public paths must not remain uninstrumented silently.

Implementation guidance:

- Add source-level helpers so diagnostics emission is easy and consistent.
- Use one Rust event builder/sanitizer as the primary path for persisted diagnostics.
- Use one Swift diagnostics client/model for app/UI emission.
- Keep categories and source names typed or centrally enumerated where practical.

The rule should be narrow enough to avoid busywork. It applies to durable workflows, bridge calls, command execution, persistence, export, user-visible failures, and public-path behavior changes. It does not require a diagnostic event for every small view-only interaction.

## Rollout Plan

Phase 1: diagnostics foundation

- Add Rust-owned diagnostic event table, model, queries, and export skeleton.
- Add privacy sanitizer and retention pruning.
- Add Swift bridge methods and a basic Diagnostics window.
- Convert current engine errors and app deletion errors into diagnostic events.
- Keep existing `engine.log` and CLI Transcript working.

Phase 2: workflow and CLI coverage

- Add workflow transition events.
- Add CLI start/finish summaries with sanitized args and job/command correlation.
- Add performance timings for bootstrap, refresh, bridge calls, command phases, and database operations.
- Link Diagnostics events to CLI Transcript.

Phase 3: export and enforcement

- Add GitHub-issue-safe export bundle.
- Add tests for redaction and retention.
- Update `AGENTS.md` and `CLAUDE.md`.
- Add plan/spec template/check script.
- Add code-review checklist language.

## Testing

Rust tests:

- Event persistence
- Filtering and summaries
- Retention pruning
- Export redaction
- Sanitized command args
- Environment snapshot redaction

Swift tests:

- Diagnostics model state
- App/UI error capture where practical
- Diagnostics window filtering assumptions where practical
- CLI Transcript link behavior from diagnostics events

Boundary validation:

- Regenerate the Swift bridge after UniFFI changes.
- Run Rust tests.
- Run Xcode build.
- Run Xcode tests when Swift or bridge code changes.

Manual smoke test:

- Bootstrap the app.
- Open Diagnostics.
- Run or simulate a New Profile command.
- Observe normal operation events.
- Observe a failure path.
- Open the related CLI Transcript.
- Export a redacted bundle and inspect it for private data.

## Success Criteria

- Normal app operation produces useful privacy-safe diagnostics.
- Errors and warnings are visible without hiding normal performance and workflow events.
- CLI Transcript remains the complete command-output tool.
- Diagnostics can link to job and command context without duplicating private output.
- Exported bundles are redacted by default and suitable for public issue reports.
- Future implementation plans must explicitly address diagnostics, privacy, and observability.
