# Initial Scaffolding Plan

## Summary

This go-around builds the **foundation only**, not the first real workflow.

The deliverable is a bootable macOS app and shared Rust engine that can:
- launch successfully,
- talk across the Swift/Rust boundary,
- initialize app storage and SQLite,
- discover and validate an Argyll installation,
- surface toolchain/app health in the UI,
- and leave the project in a state where real workflows can be added next without reworking the stack.

It does **not** build profiling, measurement, job execution, or direct instrument support yet.

## What Gets Built

### 1. Project foundation

- Create the permanent project shape: **Swift macOS app target + Rust engine crate + UniFFI binding generation**.
- Wire local build steps so the Swift app can link against the Rust engine consistently in development.
- Add a single source of truth for engine configuration: app support directory, database path, log path, and Argyll search paths.

### 2. App shell bootstrap

- Build the native macOS shell with the final top-level route structure from the product docs, but as placeholders for now:
  - Home
  - Printer Profiles
  - Troubleshoot
  - Inspect
  - B&W Tuning
  - Settings
- Only **Home** and **Settings** need real content in this pass.
- The other routes should be explicit placeholders so the navigation shape is locked early.
- The shell should also include the planned right inspector container and bottom active-work dock as structural placeholders, even though the first pass only fills them with foundation-level content.

### 3. Rust engine bootstrap

Add a minimal public engine surface:

- `EngineConfig`
- `BootstrapStatus`
- `ToolchainStatus`
- `AppHealth`
- `Engine.bootstrap(config)`
- `Engine.getToolchainStatus()`
- `Engine.setToolchainPath(path?)`
- `Engine.getAppHealth()`

Behavior for this pass:

- create required app directories if missing
- initialize SQLite and run the first migration set
- report whether Argyll was found
- report whether the expected core Argyll executables are present
- expose structured health/errors back to Swift

No workflow/job execution API yet beyond placeholder internal types needed for schema setup.

### 4. Persistence and logging scaffold

- Add initial SQLite migrations for:
  - app settings
  - toolchain/runtime status cache
  - print configurations skeleton
  - jobs skeleton
  - artifacts skeleton
- Keep schemas intentionally thin: IDs, names, timestamps, status, and path references only.
- Add structured logging in Rust and expose a simple recent-log view in the app’s technical/status area.

### 5. Argyll discovery and validation

Implement **external Argyll runtime discovery only** in this pass.

- Search order:
  1. user-configured path
  2. common/discoverable install paths
  3. shell `PATH`
- Validate presence of the core executables needed for planned printer workflows.
- Surface three states in the UI:
  - ready
  - partially available / missing tools
  - not found
- Add a Settings flow where the user can:
  - view detected path
  - override it
  - re-run validation

Do **not** bundle Argyll yet.
Do **not** enumerate instruments yet.
Do **not** launch measurement commands yet.

## Explicit Non-Goals For This Pass

- No “Create New Profile” flow
- No job state machine implementation beyond storage scaffolding
- No CLI live streaming panel tied to a real Argyll process
- No instrument detection beyond toolchain readiness
- No `nusb` or native USB/device driver work
- No advanced inspection views
- No Windows client work

## Test Plan

- Swift app launches and renders the shell on macOS.
- The shell presents the six canonical routes from the consolidated product docs.
- Rust engine loads through UniFFI and responds to bootstrap/health calls.
- First-run bootstrap creates directories and initializes SQLite cleanly.
- Re-launch uses the existing DB without migration errors.
- Argyll validation succeeds for a known-good install path.
- Argyll validation reports missing/not-found states cleanly for bad paths.
- Settings path override persists and updates displayed health.
- Placeholder routes are navigable and stable even without backend features.

## Assumptions and Defaults

- v1 remains **Argyll-first** for all real device/workflow behavior.
- This pass is strictly **initial scaffolding** for the chosen architecture.
- External Argyll installs are the only supported runtime mode in this pass, but the code should keep a clear hook for bundled runtime support later.
- The next planning round after this one should cover the **first vertical slice**, most likely toolchain-aware job creation plus one real workflow entry point.
