# New Profile Contained Refinement Plan

## Summary

This plan is the narrowest follow-up to the current `New Profile` vertical slice. It assumes the recent direction is correct and limits work to the defects that are now visible in the current slice: transcript targeting, active-work delete affordances, copy/accessibility, and task or polling behavior around the separate CLI Transcript window.

The goal is to make the recently added workflow behavior internally consistent without broadening the surface area. This plan is intentionally conservative: it should clean up the defects already exposed by the current implementation without turning into a shell-wide refactor or a guidance rewrite.

## Why Choose This Plan

Choose this plan when the immediate need is to stabilize the work already landed and close the defect class only for the public paths that were directly touched by the last pass.

This plan is appropriate if:

- the current separate transcript window is the right product direction
- the main issues are correctness and polish in the existing flow
- the team wants low churn and a short follow-up cycle
- broader shell consistency and plugin guidance can wait

Do not choose this plan if the same defect class is already visible in other live surfaces and the intent is to make the whole current shell coherent.

## What Gets Built

### 1. Transcript targeting becomes explicit

- Refactor `AppModel` so transcript loading has two separate paths:
  - open transcript for a specific job
  - load the latest resumable `new_profile` job for shell-level entry points
- Treat these as different intents, not one overloaded helper.
- Make the workflow header's `Open CLI Transcript` action always target the currently open job detail.
- Allow the footer `CLI Transcript` action to load the latest resumable job, or show an empty state if no qualifying job exists.

### 2. Transcript window stops silently retargeting

- Remove any `.task` or startup behavior in the transcript window that can override an already selected job.
- Keep the transcript window job-scoped once a job is loaded.
- Ensure the transcript window does not jump to another active job just because the dashboard refresh found a newer one.
- Handle the cases where the selected job is deleted, completed, or no longer has running commands.

### 3. Polling behavior is tightened

- Keep polling tied to the loaded job detail and command-running state.
- Stop polling when the loaded job becomes idle, is deleted, or is no longer the active transcript target.
- Avoid coupling transcript visibility to route navigation.
- Preserve the current behavior where the workflow can continue polling while the user navigates elsewhere, but only for the selected job.

### 4. Delete affordances become explicit and accessible

- Audit the active-work delete affordances already exposed in:
  - `Home`
  - bottom active-work dock
- Make the destructive action legible to VoiceOver and keyboard users.
- Add explicit accessibility labels and help text for icon-only affordances.
- Keep wording consistent across the delete button, confirmation dialog, and failure alert.

### 5. Copy and state handling are cleaned up

- Tighten destructive-action copy so it describes unpublished work removal directly and without placeholder tone.
- Audit the workflow header, transcript window, and footer transcript entry point for:
  - empty state
  - loading state
  - running command state
  - blocked or failed job state
  - deleted-job state
- Ensure the current slice uses one clear explanation for where transcript output appears.

## Likely Files Touched

The work should remain mostly in Swift and should stay closely scoped to the surfaces already changed:

- `apple/ArgyllUX/Sources/Models/AppModel.swift`
- `apple/ArgyllUX/Sources/Views/CliTranscriptWindowView.swift`
- `apple/ArgyllUX/Sources/Views/NewProfileWorkflowView.swift`
- `apple/ArgyllUX/Sources/Views/AppShellView.swift`
- `apple/ArgyllUX/Sources/Views/HomeView.swift`
- `apple/ArgyllUX/Sources/Views/ActiveWorkDockView.swift`
- `apple/ArgyllUXTests/AppModelTests.swift`

Rust and UniFFI should remain unchanged unless the engine cannot support correct transcript targeting without guesswork.

## Interface And Ownership Decisions

- The transcript window remains a separate window, not an embedded workflow panel.
- Swift owns transcript targeting, route behavior, window behavior, and presentation state.
- Rust continues to own durable job state, command state, transcript records, and persistence.
- This plan should not introduce a new abstraction unless it reduces ambiguity in the existing `AppModel` behavior.

## Validation

- `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx build`
- `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx test`
- Manual sanity pass:
  - open `New Profile`
  - open transcript from the workflow header
  - navigate to another route while transcript stays visible
  - open transcript from the footer and confirm shell-level behavior
  - delete active work from Home and from the dock
  - click `New Profile` again and confirm resume behavior
- Run `cargo test` only if Swift/Rust boundary changes become necessary.

## Stop Conditions

- If the engine does not expose enough information to keep transcript targeting correct without inference or guesswork, stop and escalate to the broader plan.
- If another live public path exposes the same defect class during this pass, note it and escalate instead of quietly leaving it behind.
- If the required fix turns into a cross-surface state redesign, stop and switch to the live-surface alignment plan.

## Assumptions And Defaults

- Latest user instruction overrides the older `CLI live panel at the bottom` wording from older docs.
- The current separate transcript window is the intended direction for the active slice.
- The objective is to close the defect class only for the already touched public paths, not to make claims about untouched placeholder workflows.
