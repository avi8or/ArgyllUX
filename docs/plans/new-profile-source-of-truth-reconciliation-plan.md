# New Profile Source Of Truth Reconciliation Plan

## Summary

This is the broadest follow-up plan. It includes the live-surface alignment work, then fixes the guidance layer that produced the open questions in the first place: repo-local plugin wording, source-of-truth precedence, and stale instructions that can still point future work toward the wrong shell shape or transcript model.

The goal is to leave both the app and the repo guidance in a state where a future engineer or agent starts from the right product shape rather than rediscovering the same ambiguity.

## Why Choose This Plan

Choose this plan when the work is no longer just about the current app code. It is the right choice when the code is drifting because the repo’s local guidance, plugin instructions, or plan docs still describe a different product shape than the one the user has now chosen.

This plan is appropriate if:

- the app behavior needs the live-surface alignment work
- the repo-local plugin bundle is likely to guide future passes on the same surfaces
- the team wants explicit precedence rules between user instruction, consolidated product docs, and plugin wording
- the cost of a larger cleanup is justified by the value of preventing repeated drift

Do not choose this plan if the immediate objective is only to fix the current app behavior and leave guidance cleanup for later.

## What Gets Built

### 1. Complete the live-surface alignment work first

- Implement everything in the live-surface alignment plan before changing repo guidance.
- Ensure the app behavior is correct before updating any source-of-truth text that describes it.
- Use the resulting app behavior as the basis for any guidance updates.

### 2. Make precedence explicit

- Capture one clear precedence order for future implementation decisions:
  1. latest user instruction
  2. consolidated product docs in `docs/projectprd/`
  3. repo-local plugin wording
- Apply that rule in the repo-local plugin guidance where Swift or shell work is routed.
- Avoid ambiguous wording that suggests plugin docs can override current product docs.

### 3. Reconcile repo-local plugin guidance with the current shell

- Review `plugins/argyllux-apple-client/skills/argyllux-apple-client/SKILL.md` and relevant bundled skill text for wording that conflicts with:
  - the current top-level route model
  - the current `New Profile` shell behavior
  - the current transcript-window behavior
- Update local guidance so future passes are pointed toward:
  - separate transcript window behavior
  - job-specific transcript targeting from workflow contexts
  - shell-level transcript targeting from shell contexts
  - the correct ownership boundary between Swift and Rust

### 4. Reconcile local plan and reference material where needed

- Add or update one repo-local note or plan reference that captures the verification boundary between:
  - build/test verified
  - macOS UI verified
  - real Argyll operator-verified
- Keep this lightweight and operational rather than turning it into a large process document.
- Only update consolidated product docs if they are actually wrong, not merely older than the latest user override.

### 5. Recheck Swift/Rust boundary clarity

- Re-evaluate whether the current Swift/Rust boundary is still coarse-grained enough once the shell behavior and guidance are aligned.
- Add bridge surface only if it reduces caller ambiguity and keeps durable logic in Rust.
- Do not solve guidance drift by pushing durable logic into Swift.

### 6. Leave future implementers with one coherent path

- Ensure the final repo state tells a future implementer:
  - where transcript state belongs
  - how `New Profile` resume-vs-create behavior works
  - which source of truth to trust when docs disagree
  - what level of verification has actually been achieved

## Likely Files Touched

This plan is broader than the other two and may touch both code and guidance:

- Swift files from the live-surface alignment plan
- `plugins/argyllux-apple-client/skills/argyllux-apple-client/SKILL.md`
- related bundled skill docs if they materially steer this work
- one repo-local plan or reference file under `docs/plans/` or a nearby guidance location

Consolidated product docs in `docs/projectprd/` should only be changed if they are genuinely incorrect and not simply older than the latest explicit user instruction.

## Interface And Ownership Decisions

- The transcript model remains a separate window, not an embedded workflow panel.
- Swift owns route behavior, window behavior, transcript presentation, and shell-level interaction rules.
- Rust owns durable job identity, workflow state, command transcripts, and persistence.
- Guidance should describe the shipped behavior, not an earlier draft of the product.

## Validation

- `cargo test`
- `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx build`
- `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx test`
- `python3 /Users/tylermiller/.codex/skills/code-enforcer/scripts/code_enforcer.py --allow-repo-inspection`
- Manual macOS UI walkthrough
- Manual transcript-window walkthrough during a real command run if a known-good Argyll install is available

## Stop Conditions

- If fixing the guidance layer requires rewriting consolidated product docs that are still directionally correct, stop and ask before expanding scope.
- If the guidance drift turns out to be broader than the `New Profile` and transcript slice, split that into a separate guidance pass instead of silently widening this one.
- Do not use this plan to smuggle in unrelated cleanup or speculative architecture changes.

## Assumptions And Defaults

- This plan is only worth choosing if the goal includes preventing the same drift from recurring in future sessions.
- It is acceptable to leave consolidated product docs unchanged when the latest user instruction is the only override and that override is already clearly captured in repo-local guidance.
- The desired end state is both correct app behavior and correct implementation guidance for the next pass.
