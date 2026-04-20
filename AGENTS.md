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

If editing the repo-local plugin itself, also use `plugin-creator`. If adding or revising one of its bundled skills, also use `skill-creator` or `skill-forge`.

### Global skills that matter in this repo

- `rust-desktop-dev`: default for `rust/**/*.rs`, workspace `Cargo.toml`, SQLite/state changes, subprocess/toolchain logic, and Rust tests.
- `serena-integration`: use alongside existing-code work if Serena tools are actually available in the session. If they are not exposed, fall back to `rg`, `nl`, and targeted file reads without blocking.
- `code-enforcer`: use as the final gate for substantial changes.
- `github:gh-address-comments`, `github:gh-fix-ci`, `github:yeet`: use when the user asks for PR review work, CI debugging, or publish/push/PR tasks.
- `pdf`, `spreadsheet`, `Excel`, `PowerPoint`: only when the user explicitly asks for those artifact types.

### Plugins and skills to avoid by default here

These are available in the environment, but they are not the default path for this repo:

- `Iced Rust Desktop`: this repo is not an Iced UI app. Do not route normal `rust/engine` work through Iced-specific guidance unless the user explicitly asks for Iced comparisons or shared Rust desktop patterns.
- `Build Web Apps`, `Vercel`, `Cloudflare`, `Playwright`, `webapp-testing`: do not default to web/browser skills for the native macOS client.
- `Figma`: use only when the user explicitly asks for design or Figma work.
- `Computer Use`: use only when live visual inspection of the built macOS app is necessary and shell/build evidence is not enough.

## Ownership Rules

Decide ownership before editing cross-boundary features.

- Rust owns workflow state, job lifecycle, command orchestration, toolchain validation, SQLite persistence, logs, artifacts, and Argyll behavior.
- Swift owns presentation, local view state, app lifecycle, menus, sheets, window behavior, file pickers, and platform integration.
- Keep the bridge coarse-grained. Do not move durable logic into Swift just because the UI needs it.
- Do not introduce `SwiftData`, `Core Data`, or ad hoc JSON state stores for product data that belongs in the Rust engine.

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
