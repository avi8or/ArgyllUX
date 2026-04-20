# New Profile Live Surface Alignment Plan

## Summary

This plan treats the recent defects as a live-shell consistency problem rather than a narrow cleanup. It updates every currently live public path that can launch, resume, display, delete, or inspect `New Profile` work so the user gets one coherent behavior across the current shell.

The goal is not to add new workflow capability. The goal is to make the work that already exists behave as one product surface instead of a set of individually fixed entry points.

## Why Choose This Plan

Choose this plan when the intended deliverable is a coherent current shell for the `new_profile` slice, not just a patch to the most recent changes.

This plan is appropriate if:

- `New Profile` is already the primary real workflow in the app
- the user should be able to move between Home, the dock, the workflow screen, Settings handoff, and Printer Profiles without seeing conflicting behavior
- the current state model in Swift is starting to blur “active workflow,” “opened job,” and “transcript target”
- the team wants to be able to say the current live public paths are aligned

Do not choose this plan if the real issue is stale repo guidance or conflicting plugin instructions. That requires the broader reconciliation plan.

## What Gets Built

### 1. Live public entry points resolve through one job-opening model

- Normalize how the app opens `new_profile` work from:
  - Home launcher
  - Home active-work list
  - bottom active-work dock
  - workflow header
  - footer transcript entry point
  - Settings handoff that seeds `New Profile`
  - Printer Profiles handoff back to the originating job, where already exposed
- Define one rule for resume-vs-create behavior:
  - if a resumable `new_profile` job exists, `New Profile` resumes it
  - if not, create a new draft
- Remove any path-specific exceptions that can create duplicate active work.

### 2. Transcript targeting becomes a first-class Swift concern

- Introduce explicit transcript-target state in Swift instead of overloading `activeNewProfileDetail` for both workflow presentation and transcript selection.
- Keep job-level transcript entry points job-specific.
- Keep shell-level transcript entry points shell-specific.
- Ensure the transcript window stays independent from route navigation and does not silently switch jobs.
- Define what should happen when:
  - there is no active job
  - the transcript target job is deleted
  - the transcript target job is blocked or failed
  - the transcript target job is completed but unpublished

### 3. Delete behavior is consistent everywhere active work is shown

- Make active work deletable from every currently live public surface that shows it.
- Standardize button labels, accessibility labels, help text, confirmation copy, and error copy.
- Keep deletion behavior consistent whether initiated from Home, the dock, or another live public path added during this pass.
- Confirm the user can recover context after deletion, including what `New Profile` does next.

### 4. Empty, loading, and error states are aligned

- Audit and align visible states across the current `new_profile` slice:
  - no active job
  - opening job detail
  - deleted job
  - blocked job
  - failed job
  - running command
  - completed but unpublished work
- Keep the explanation of transcript output, job identity, and next action consistent across workflow and transcript surfaces.
- Ensure no public path leaves the user at a dead end.

### 5. AppModel state ownership is simplified

- Revisit `AppModel` ownership for:
  - selected route
  - active workflow
  - active job detail
  - transcript target
  - polling lifecycle
- Keep the number of concepts small and explicit.
- Avoid spreading job-selection rules across multiple call sites.
- Add only the abstractions needed to reduce ambiguity and caller burden.

## Likely Files Touched

Most of the work should stay in the existing Swift shell and test surface:

- `apple/ArgyllUX/Sources/Models/AppModel.swift`
- `apple/ArgyllUX/Sources/Views/AppShellView.swift`
- `apple/ArgyllUX/Sources/Views/HomeView.swift`
- `apple/ArgyllUX/Sources/Views/ActiveWorkDockView.swift`
- `apple/ArgyllUX/Sources/Views/NewProfileWorkflowView.swift`
- `apple/ArgyllUX/Sources/Views/CliTranscriptWindowView.swift`
- `apple/ArgyllUX/Sources/Views/SettingsView.swift`
- `apple/ArgyllUX/Sources/Views/AppShellView.swift`
- `apple/ArgyllUXTests/AppModelTests.swift`

If the current dashboard/job-detail split in the engine is too ambiguous to support these rules cleanly, add a minimal Rust or UniFFI surface rather than layering inference into Swift.

## Interface And Ownership Decisions

- The transcript window remains a separate, job-scoped window.
- Swift owns route behavior, window behavior, transcript-target selection, and current-shell presentation rules.
- Rust owns durable job identity, command records, transcript persistence, and workflow/job lifecycle.
- Shell-level entry points and job-level entry points are allowed to have different selection rules, but those rules must be explicit and shared.

## Validation

- `cargo test` if bridge or engine changes are needed
- `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx build`
- `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx test`
- Manual UI pass across all current live paths listed above
- Final gate:
  - `python3 /Users/tylermiller/.codex/skills/code-enforcer/scripts/code_enforcer.py --allow-repo-inspection`

## Stop Conditions

- If repo docs or plugin guidance are materially steering future work in the wrong direction, stop and escalate instead of papering over that drift in Swift only.
- If the only clean fix requires reworking source-of-truth guidance or plan docs, switch to the broader reconciliation plan.
- Do not claim the whole product is aligned when placeholder workflows outside the `new_profile` slice remain unchanged.

## Assumptions And Defaults

- This plan is the right default if the goal is to say the current live public paths for `New Profile` are coherent.
- Latest explicit user instruction overrides the older embedded panel wording.
- Placeholder workflows outside the current `new_profile` slice remain out of scope.
