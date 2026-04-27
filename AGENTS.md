# ArgyllUX Repo Instructions

This file complements the global Codex instructions. Follow the global file for general operating standards, code quality, UI review, verification, and final response requirements. Use this file only for ArgyllUX-specific routing, source-of-truth docs, and validation.

## Repo Shape

ArgyllUX is a native macOS app with a Rust core and a generated Swift bridge.

- `apple/ArgyllUX/` is the SwiftUI macOS client.
- `apple/ArgyllUXTests/` is the Swift test target.
- `rust/engine/` owns workflow logic, SQLite persistence, logging, toolchain discovery, and Argyll orchestration.
- `rust/tools/uniffi-bindgen/` and `scripts/build-swift-bridge.sh` own bridge generation.
- `docs/projectprd/` is the product and workflow source of truth.
- `docs/argyll-reference/` is the local ArgyllCMS reference set.
- `plugins/argyllux-apple-client/` is the repo-local plugin bundle for Apple-client work.

Treat `README.md` as high-level context only. Verify claims against the current code and docs before repeating them.

## Read Order

Read only the slices relevant to the task, but prefer these docs before making product or UI decisions:

1. `docs/projectprd/00-product-overview.md`
2. `docs/projectprd/01-information-architecture.md`
3. `docs/projectprd/02-workflows-and-state-machines.md`
4. `docs/projectprd/03-screen-specs.md`
5. `docs/projectprd/06-ui-copy-and-controls.md`

For ArgyllCMS behavior, command sequencing, file semantics, or instrument assumptions, consult `docs/argyll-reference/` before guessing or browsing elsewhere.

If repo-local plugin wording conflicts with the consolidated product docs, the files in `docs/projectprd/` win.

## Instruction File Parity

Keep `AGENTS.md` and `CLAUDE.md` identical. When one changes, update the other in the same change and verify parity before finalizing.

## Current UI Direction And Layout Mandate

ArgyllUX is moving toward persistent shell chrome and route-owned panes, not large scrolling pages. Treat this as product direction, not visual polish.

- Avoid scrolling in the app as much as practical. Scrolling is acceptable for long data sets, logs, transcripts, and dense editors, but it should not be the default answer for primary workflow layout.
- Do not build a whole route as one large vertical `ScrollView` with a `2/3 + 1/3` content split. That pattern hides context, makes the next action harder to find, and pushes layout work onto the user.
- Keep high-value context outside the main scroller. Use fixed headers, persistent sidebars, inspectors, docks, and footer/status surfaces so workflow identity, stage, readiness, and next actions remain visible.
- Use the route-owned left sidebar more effectively for catalog browsing, item lists, hierarchy, workflow progress, and timeline/context surfaces. A sidebar should reduce main-area clutter, not duplicate top-level navigation.
- Prefer layouts where the center work surface is focused on the current task, with supporting context moved into a left sidebar, right utility inspector, bottom active-work dock, or modal sheet as appropriate.
- If a screen seems to need broad scrolling to work, first reconsider its information architecture: split navigation from details, move persistent context into shell chrome, collapse secondary sections, or introduce a focused detail pane.
- When modifying one layout pattern, check neighboring screens for the same scrolling or misplaced-context pattern. Do not leave the same defect class in parallel public paths without calling it out.

## Skill And Plugin Routing

### Repo-local plugin: `argyllux-apple-client`

Use the local `argyllux-apple-client` plugin whenever the task touches:

- `apple/ArgyllUX/**/*.swift`
- `apple/ArgyllUXTests/**/*.swift`
- the Swift/Rust boundary
- interface copy inside the macOS app
- `plugins/argyllux-apple-client/`

Layer its bundled skills like this:

- `argyllux-apple-client`: first pass for Apple-client architecture and Swift/Rust ownership.
- `swiftui-ui-patterns`: screen structure, navigation, settings layouts, sheets, split views, reusable SwiftUI composition.
- `writing-for-interfaces`: labels, helper text, warnings, empty states, dialogs, settings descriptions, status copy.
- `swiftui-pro`: final SwiftUI correctness, accessibility, modern API, and hygiene pass.
- `swift-concurrency-pro`: actors, task lifecycles, async bridging, isolation, continuation/cancellation bugs.
- `swift-testing-pro`: Swift Testing work in `apple/ArgyllUXTests/`.

The repo-local plugin also exposes these workflow commands:

- `/argyllux-apple-client:review-apple-client`
- `/argyllux-apple-client:implement-swift-screen`
- `/argyllux-apple-client:review-interface-copy`
- `/argyllux-apple-client:validate-apple-client`

If editing the repo-local plugin itself, also use `plugin-creator`. If adding or revising one of its bundled skills, also use `skill-creator` or `skill-forge`.

### Installed OpenAI plugin: `Build macOS Apps`

Use OpenAI's `Build macOS Apps` plugin as a supporting plugin when the task is primarily about macOS platform mechanics rather than ArgyllUX product behavior, especially for:

- Xcode project or scheme discovery
- local build/run wiring and Codex Run-button setup
- macOS test triage
- AppKit interop
- window management and multiwindow behavior
- view-file refactors
- signing, entitlements, packaging, and notarization
- macOS logging and telemetry

Prefer this layering when it applies:

- `argyllux-apple-client` first for ArgyllUX-specific architecture, ownership, workflow language, and screen behavior
- `build-run-debug` for build/run/debug entrypoints and shell-first macOS execution
- `test-triage` for failing macOS tests
- `appkit-interop` for representables, responder-chain behavior, panels, or other desktop-only native bridges
- `window-management` for titlebar, toolbar, placement, restore, launch, or multiwindow behavior
- `swiftui-patterns` or `view-refactor` when the problem is SwiftUI structure rather than product workflow semantics
- `signing-entitlements` or `packaging-notarization` for distribution issues
- `telemetry` when the task needs `Logger`/`os.Logger` instrumentation or runtime-event inspection

Do not let `Build macOS Apps` replace the repo-local Apple-client plugin for product decisions, copy, or Swift-versus-Rust ownership. Treat it as the platform specialist paired with ArgyllUX's local source-of-truth plugin.

### Global skills that matter in this repo

- `rust-desktop-dev`: default for `rust/**/*.rs`, workspace `Cargo.toml`, SQLite/state changes, subprocess/toolchain logic, and Rust tests.
- `serena-integration`: use alongside existing-code work if Serena tools are actually available in the session. If they are not exposed, fall back to `rg`, `nl`, and targeted file reads without blocking.
- `code-enforcer`: use as the final gate for substantial changes.
- `github:gh-address-comments`, `github:gh-fix-ci`, `github:yeet`: use when the user asks for PR review work, CI debugging, or publish/push/PR tasks.
- `pdf`, `spreadsheet`, `Excel`, `PowerPoint`: only when the user explicitly asks for those artifact types.

### Plugins and skills to avoid by default here

These are available in the environment, but they are not the default path for this repo:

- `Iced Rust Desktop`: this repo is not an Iced UI app. Do not route normal `rust/engine` work through Iced-specific guidance unless the user explicitly asks for Iced comparisons or shared Rust desktop patterns.
- `Build macOS Apps`: useful here when installed, but use it as a companion for macOS platform mechanics rather than as a substitute for `argyllux-apple-client` or the product docs.
- `Build Web Apps`, `Vercel`, `Cloudflare`, `Playwright`, `webapp-testing`: do not default to web/browser skills for the native macOS client.
- `Figma`: use only when the user explicitly asks for design or Figma work.
- `Computer Use`: use only when live visual inspection of the built macOS app is necessary and shell/build evidence is not enough.

## Ownership Rules

Decide ownership before editing cross-boundary features.

- Rust owns workflow state, job lifecycle, command orchestration, toolchain validation, SQLite persistence, logs, artifacts, and Argyll behavior.
- Swift owns presentation, local view state, app lifecycle, menus, sheets, window behavior, file pickers, and platform integration.
- Keep the bridge coarse-grained. Do not move durable logic into Swift just because the UI needs it.
- Do not introduce `SwiftData`, `Core Data`, or ad hoc JSON state stores for product data that belongs in the Rust engine.

## Diagnostics, Privacy, And Observability

For durable workflows, bridge calls, command execution, persistence, export, user-visible failures, or public-path behavior changes, plans and implementation must explicitly address diagnostics.

- Emit structured diagnostics through the Rust-owned diagnostics store for normal operation, warnings, errors, performance timings, and sanitized environment context.
- Do not record private user data in global diagnostics: file contents, measurement contents, ICC/profile bytes, CGATS rows, user notes, arbitrary stdout/stderr, hostnames, usernames, serial numbers, device identifiers, network information, full filesystem inventories, or user-entered profile/printer/paper/Issue Case names.
- Keep full command output in the job-scoped CLI Transcript. Diagnostics may store command kind, sanitized argument shape, status, duration, exit code, and correlation IDs.
- Exported diagnostics must be redacted by default and suitable for a public GitHub issue unless the user explicitly includes CLI transcripts or local paths.
- When adding diagnostics to one public path, check neighboring same-class public paths and either instrument them or state what remains.

## Bridge And Generated Code Rules

- Do not hand-edit files in `apple/ArgyllUX/Bridge/Generated/`.
- When the UniFFI surface changes, regenerate the bridge with `scripts/build-swift-bridge.sh` or the equivalent Xcode build step.
- After Rust-side API changes, confirm the Swift target still compiles before considering the change done.

## Validation

Choose the smallest relevant validation set, but use these defaults:

- Rust-only changes: `cargo test`
- Swift-only changes: `xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx build`
- Swift test changes: `xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx test`
- Swift/Rust boundary changes: run all three
  - `cargo test`
  - `xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx build`
  - `xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx test`

If you skip a relevant check, say so explicitly.

## Product Language

- Prefer the user-facing terms from `docs/projectprd/00-product-overview.md` and `docs/projectprd/06-ui-copy-and-controls.md`.
- Keep interface language task-focused and plain. Do not drift into Argyll command names in primary UI copy unless the surface is explicitly technical.
- For workflow work, keep the job states and stage sequencing aligned with `docs/projectprd/02-workflows-and-state-machines.md`.
