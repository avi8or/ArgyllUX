# New Profile Source Of Truth Note

This note keeps the active `New Profile` slice aligned when older docs, local plugin wording, and recent user direction do not all say the same thing.

## Precedence

Use this order when the sources disagree:

1. latest user instruction
2. consolidated product docs in `docs/projectprd/`
3. repo-local plugin wording

Do not treat repo-local plugin guidance as a license to override the consolidated product docs.

## Current Slice Decisions

For the current `New Profile` and transcript slice:

- The top-level shell routes are `Home`, `Printer Profiles`, `Troubleshoot`, `Inspect`, `B&W Tuning`, and `Settings`.
- `New Profile` shell launchers resume the latest resumable `new_profile` job first. They create a new draft only when no resumable job exists.
- The CLI transcript is a separate window, not an embedded workflow panel.
- Workflow-context transcript actions target the currently opened job.
- Shell-context transcript actions target the latest resumable `new_profile` job without silently retargeting the workflow detail.
- Swift owns route behavior, window behavior, transcript targeting, and shell presentation rules.
- Rust owns durable job identity, workflow state, command transcripts, persistence, and Argyll orchestration.

Some older planning and screen-spec text still describes a bottom CLI panel. For the active slice, the separate transcript window is the current override.

## Verification Boundary

Use these labels precisely in plans, reviews, and final responses:

- `build/test verified`: automated checks such as `cargo test`, `xcodebuild`, and similar repo gates passed.
- `macOS UI verified`: a human manually exercised the built macOS app and confirmed the behavior in the native UI.
- `real Argyll operator-verified`: the workflow was exercised against a known-good Argyll installation and, where relevant, real device or print/operator conditions.

Do not collapse these into one blanket claim. If only build/test verification ran, say so directly.

## Update Rule

Only edit `docs/projectprd/` when those docs are genuinely wrong. If the current slice is following a newer explicit user override, capture that override in repo-local guidance and call out the boundary rather than silently rewriting the consolidated product docs.
