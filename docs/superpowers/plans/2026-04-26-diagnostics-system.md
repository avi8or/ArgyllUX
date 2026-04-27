# Diagnostics System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a production-safe diagnostics system that records structured, privacy-safe app and engine events, replaces the narrow Error Log Viewer with Diagnostics, preserves the CLI Transcript as the full command-output surface, and adds redacted issue-report export plus process enforcement.

**Architecture:** Rust owns durable diagnostics persistence, retention, sanitization, summaries, command summary events, export assembly, and environment facts. Swift owns presentation and UI-originated event emission through coarse bridge methods; it never writes an alternate diagnostics store. The CLI Transcript remains job-scoped and full-fidelity, while Diagnostics stores summaries and correlation IDs.

**Tech Stack:** Rust, rusqlite, serde/serde_json, UniFFI, SwiftUI, Swift Testing, shell scripts, Xcode build/test.

---

## Scope Check

The spec spans three phases, but the parts form one diagnostics subsystem with a shared event model and bridge. This plan keeps it as one implementation plan while making each task independently testable:

- Tasks 1-3 establish the Rust-owned foundation and bridge.
- Tasks 4-5 replace the live Swift UI surface and add app/UI emission.
- Tasks 6-7 add workflow, CLI, performance, export, and transcript correlation.
- Task 8 adds process enforcement.
- Task 9 runs the full validation and manual smoke test.

## Source Context

Read these files before editing:

- `docs/superpowers/specs/2026-04-26-diagnostics-system-design.md`
- `docs/projectprd/00-product-overview.md`
- `docs/projectprd/01-information-architecture.md`
- `docs/projectprd/02-workflows-and-state-machines.md`
- `docs/projectprd/03-screen-specs.md`
- `docs/projectprd/06-ui-copy-and-controls.md`
- `docs/plans/new-profile-source-of-truth-note.md`
- `AGENTS.md`
- `CLAUDE.md`

Current source surfaces:

- `rust/engine/src/logging.rs` appends newline-delimited `engine.log` records.
- `rust/engine/src/model.rs` contains UniFFI records and enums.
- `rust/engine/src/db.rs` owns the SQLite schema and current job/transcript persistence.
- `rust/engine/src/runner.rs` owns Argyll command execution and full CLI transcript writes.
- `rust/engine/src/lib.rs` owns the exported `Engine` bridge.
- `apple/ArgyllUX/Sources/Views/LogViewerSheetView.swift` is the current Error Log Viewer to replace.
- `apple/ArgyllUX/Sources/Models/Shell/CliTranscriptModel.swift` and `apple/ArgyllUX/Sources/Views/CliTranscriptWindowView.swift` are the transcript surface to preserve.

## File Structure

Create:

- `rust/engine/src/diagnostics.rs`
  Owns diagnostic builders, sanitization, redaction, environment snapshots, retention constants, and export assembly helpers.

- `apple/ArgyllUX/Sources/Models/Shell/DiagnosticsModel.swift`
  Owns Diagnostics window state, filtering, refresh, export status, and transcript-link requests.

- `apple/ArgyllUX/Sources/Views/DiagnosticsWindowView.swift`
  Replaces the current error-only sheet with a dedicated Diagnostics window.

- `apple/ArgyllUXTests/DiagnosticsModelTests.swift`
  Tests Swift filtering, summary state, export status, and command-linked transcript requests.

- `docs/superpowers/templates/implementation-spec-template.md`
  Adds the required `Diagnostics, Privacy, And Observability` section for new specs/plans.

- `docs/superpowers/code-review-checklist.md`
  Adds review guidance for diagnostics coverage and same-class public paths.

- `scripts/check-diagnostics-section.sh`
  Fails changed relevant plan/spec docs that omit the diagnostics section.

Modify:

- `rust/engine/src/model.rs`
  Adds UniFFI diagnostic enums and records.

- `rust/engine/src/db.rs`
  Adds the `diagnostic_events` table, indexes, persistence queries, retention pruning, summary queries, export data loading, and tests.

- `rust/engine/src/lib.rs`
  Exports coarse diagnostic bridge methods and records bootstrap/toolchain/persistence failures.

- `rust/engine/src/runner.rs`
  Records CLI start/finish summaries, command durations, sanitized argument shapes, and failure summaries without duplicating stdout/stderr.

- `rust/engine/src/logging.rs`
  Remains compatibility-only for `engine.log`; add a module comment that the SQLite diagnostics table is authoritative.

- `scripts/build-swift-bridge.sh`
  No logic change expected; run it after UniFFI model/method changes.

- `apple/ArgyllUX/Sources/Models/EngineBridge.swift`
  Adds async actor wrappers for diagnostic bridge methods.

- `apple/ArgyllUX/Sources/Models/AppModel.swift`
  Owns `DiagnosticsModel`, routes footer/window actions, and emits UI-originated events for durable actions and visible failures.

- `apple/ArgyllUX/Sources/App/ArgyllUXApp.swift`
  Adds the Diagnostics window scene.

- `apple/ArgyllUX/Sources/Views/AppShellView.swift`
  Opens the Diagnostics window from the footer and removes the error-log sheet.

- `apple/ArgyllUX/Sources/Views/FooterStatusBarView.swift`
  Renames `Error Log Viewer` to `Diagnostics`.

- `apple/ArgyllUX/Sources/Views/LogViewerSheetView.swift`
  Delete after `DiagnosticsWindowView` is wired.

- `apple/ArgyllUXTests/Support/AppModelTestSupport.swift`
  Extends `FakeEngine` for the new bridge methods and diagnostic records.

- `apple/ArgyllUXTests/AppModelShellTests.swift`
  Verifies bootstrap leaves diagnostics ready and deletion failures emit diagnostics.

- `apple/ArgyllUXTests/CliTranscriptModelTests.swift`
  Keep current transcript behavior unchanged; add no diagnostics assertions unless transcript linking changes that model.

- `AGENTS.md` and `CLAUDE.md`
  Add identical diagnostics process guidance.

## Data Model Decisions

- Store `details_json` as sanitized JSON text instead of exposing maps over UniFFI.
- Use typed `DiagnosticLevel`, `DiagnosticCategory`, and `DiagnosticPrivacy` enums in the bridge.
- Keep event payloads bounded to 64 KB after sanitization.
- Store only stable correlation IDs: `job_id`, `command_id`, `profile_id`, and `issue_case_id`.
- Keep `engine.log` as a compatibility/debug artifact, but do not build new UI on it.
- Store command output only in `job_command_events`; diagnostics records command summaries and links.

## Diagnostics, Privacy, And Observability

This implementation is the project-level observability foundation. Each task below prevents private user data from entering the global diagnostics stream before it is persisted, not only during export. The export task re-applies redaction so old or malformed rows cannot leak full user paths or private labels into a shareable bundle.

---

### Task 1: Rust Diagnostic Types And Sanitizer

**Files:**
- Create: `rust/engine/src/diagnostics.rs`
- Modify: `rust/engine/src/model.rs`
- Modify: `rust/engine/src/lib.rs`
- Test: `rust/engine/src/diagnostics.rs`

- [ ] **Step 1: Write failing sanitizer tests**

Add this module to the bottom of the new file `rust/engine/src/diagnostics.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{DiagnosticCategory, DiagnosticEventInput, DiagnosticLevel, DiagnosticPrivacy};

    fn input_with_details(details_json: &str) -> DiagnosticEventInput {
        DiagnosticEventInput {
            level: DiagnosticLevel::Info,
            category: DiagnosticCategory::Cli,
            source: "engine.cli".to_string(),
            message: "Command finished.".to_string(),
            details_json: details_json.to_string(),
            privacy: DiagnosticPrivacy::Internal,
            job_id: Some("job-1".to_string()),
            command_id: Some("command-1".to_string()),
            profile_id: None,
            issue_case_id: None,
            duration_ms: Some(42000),
            operation_id: Some("op-1".to_string()),
            parent_operation_id: None,
        }
    }

    #[test]
    fn sanitizer_redacts_private_payload_values_before_persistence() {
        let sanitized = sanitize_event_input(input_with_details(
            r#"{
                "profile_name":"P900 Rag v3",
                "path":"/Users/tylermiller/Profiles/P900 Rag v3.icc",
                "stdout":"secret command output",
                "argv":["/opt/homebrew/bin/targen","-v","/Users/tylermiller/job/p900"]
            }"#
        ));

        assert_eq!(sanitized.message, "Command finished.");
        assert!(sanitized.details_json.contains("\"profile_name\":\"[redacted]\""));
        assert!(sanitized.details_json.contains("\"path\":\"$HOME/.../P900 Rag v3.icc\""));
        assert!(sanitized.details_json.contains("\"stdout\":\"[redacted]\""));
        assert!(sanitized.details_json.contains("\"argv\":[\"targen\",\"-v\",\"$HOME/.../p900\"]"));
        assert_eq!(sanitized.privacy, DiagnosticPrivacy::SensitiveRedacted);
    }

    #[test]
    fn sanitizer_limits_payload_size_after_redaction() {
        let large_value = "x".repeat(MAX_DIAGNOSTIC_DETAILS_BYTES + 100);
        let sanitized = sanitize_event_input(input_with_details(
            &serde_json::json!({ "safe": large_value }).to_string(),
        ));

        assert!(sanitized.details_json.len() <= MAX_DIAGNOSTIC_DETAILS_BYTES);
        assert!(sanitized.details_json.contains("truncated"));
    }

    #[test]
    fn path_category_hides_private_path_details() {
        assert_eq!(
            path_category(Some("/Users/tylermiller/bin/argyll")),
            "user_home"
        );
        assert_eq!(
            path_category(Some("/Applications/ArgyllCMS/bin")),
            "applications"
        );
        assert_eq!(path_category(None), "not_resolved");
    }
}
```

- [ ] **Step 2: Run the failing sanitizer tests**

Run:

```bash
cargo test -p argyllux_engine diagnostics::tests -- --nocapture
```

Expected: FAIL because `rust/engine/src/diagnostics.rs`, `DiagnosticEventInput`, `DiagnosticLevel`, `DiagnosticCategory`, and `DiagnosticPrivacy` do not exist yet.

- [ ] **Step 3: Add diagnostic UniFFI records and enums**

In `rust/engine/src/model.rs`, insert these types after `CommandStream`:

```rust
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum DiagnosticLevel {
    Debug,
    Info,
    Warning,
    Error,
    Critical,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum DiagnosticCategory {
    App,
    Ui,
    Workflow,
    Engine,
    Cli,
    Database,
    Toolchain,
    Performance,
    Environment,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum DiagnosticPrivacy {
    Public,
    Internal,
    SensitiveRedacted,
}
```

In the same file, insert these records after `LogEntry`:

```rust
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct DiagnosticEventInput {
    pub level: DiagnosticLevel,
    pub category: DiagnosticCategory,
    pub source: String,
    pub message: String,
    pub details_json: String,
    pub privacy: DiagnosticPrivacy,
    pub job_id: Option<String>,
    pub command_id: Option<String>,
    pub profile_id: Option<String>,
    pub issue_case_id: Option<String>,
    pub duration_ms: Option<u32>,
    pub operation_id: Option<String>,
    pub parent_operation_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct DiagnosticEventRecord {
    pub id: String,
    pub timestamp: String,
    pub level: DiagnosticLevel,
    pub category: DiagnosticCategory,
    pub source: String,
    pub message: String,
    pub details_json: String,
    pub privacy: DiagnosticPrivacy,
    pub job_id: Option<String>,
    pub command_id: Option<String>,
    pub profile_id: Option<String>,
    pub issue_case_id: Option<String>,
    pub duration_ms: Option<u32>,
    pub operation_id: Option<String>,
    pub parent_operation_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct DiagnosticEventFilter {
    pub levels: Vec<DiagnosticLevel>,
    pub categories: Vec<DiagnosticCategory>,
    pub search_text: Option<String>,
    pub job_id: Option<String>,
    pub profile_id: Option<String>,
    pub since_timestamp: Option<String>,
    pub until_timestamp: Option<String>,
    pub errors_only: bool,
    pub limit: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct DiagnosticsRetentionStatus {
    pub retained_days: u32,
    pub max_storage_mb: u32,
    pub max_payload_bytes: u32,
    pub event_count: u32,
    pub estimated_storage_bytes: u64,
    pub last_pruned_at: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct DiagnosticsSummary {
    pub total_count: u32,
    pub warning_count: u32,
    pub error_count: u32,
    pub critical_count: u32,
    pub latest_critical_message: Option<String>,
    pub latest_event_timestamp: Option<String>,
    pub app_readiness: String,
    pub argyll_version: String,
    pub argyll_path_category: String,
    pub retention: DiagnosticsRetentionStatus,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct DiagnosticsExportOptions {
    pub output_directory: String,
    pub include_cli_transcripts: bool,
    pub include_local_paths: bool,
    pub job_ids: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct DiagnosticsExportResult {
    pub success: bool,
    pub bundle_path: String,
    pub message: String,
    pub included_event_count: u32,
    pub included_transcript_count: u32,
    pub redacted_paths_count: u32,
}
```

- [ ] **Step 4: Add the diagnostics module implementation**

Create `rust/engine/src/diagnostics.rs` with this initial implementation:

```rust
use crate::model::{
    DiagnosticCategory, DiagnosticEventInput, DiagnosticEventRecord, DiagnosticLevel,
    DiagnosticPrivacy, DiagnosticsRetentionStatus, ToolchainStatus,
};
use crate::support::{EngineResult, iso_timestamp};
use serde_json::{Map, Value, json};
use std::path::Path;

pub const DEFAULT_RETENTION_DAYS: u32 = 30;
pub const DEFAULT_MAX_STORAGE_MB: u32 = 50;
pub const MAX_DIAGNOSTIC_DETAILS_BYTES: usize = 64 * 1024;

const PRIVATE_VALUE_KEYS: &[&str] = &[
    "profile_name",
    "printer_name",
    "paper_name",
    "issue_case_title",
    "notes",
    "stdout",
    "stderr",
    "hostname",
    "username",
    "serial_number",
    "device_identifier",
    "network",
];

const PATH_KEYS: &[&str] = &[
    "path",
    "file_path",
    "workspace_path",
    "profile_path",
    "measurement_path",
    "resolved_install_path",
];

#[derive(Debug, Clone)]
pub(crate) struct SanitizedDiagnosticEventInput {
    pub level: DiagnosticLevel,
    pub category: DiagnosticCategory,
    pub source: String,
    pub message: String,
    pub details_json: String,
    pub privacy: DiagnosticPrivacy,
    pub job_id: Option<String>,
    pub command_id: Option<String>,
    pub profile_id: Option<String>,
    pub issue_case_id: Option<String>,
    pub duration_ms: Option<u32>,
    pub operation_id: Option<String>,
    pub parent_operation_id: Option<String>,
}

pub(crate) fn sanitize_event_input(input: DiagnosticEventInput) -> SanitizedDiagnosticEventInput {
    let mut privacy = input.privacy.clone();
    let mut details = serde_json::from_str::<Value>(&input.details_json).unwrap_or_else(|_| {
        if input.details_json.trim().is_empty() {
            json!({})
        } else {
            json!({ "raw": input.details_json })
        }
    });

    if sanitize_json_value(&mut details) {
        privacy = DiagnosticPrivacy::SensitiveRedacted;
    }

    let mut details_json = serde_json::to_string(&details).unwrap_or_else(|_| "{}".to_string());
    if details_json.len() > MAX_DIAGNOSTIC_DETAILS_BYTES {
        details_json = truncate_details_json(&details);
        privacy = DiagnosticPrivacy::SensitiveRedacted;
    }

    SanitizedDiagnosticEventInput {
        level: input.level,
        category: input.category,
        source: trim_or_fallback(&input.source, "unknown"),
        message: trim_or_fallback(&input.message, "Diagnostic event recorded."),
        details_json,
        privacy,
        job_id: trim_option(input.job_id),
        command_id: trim_option(input.command_id),
        profile_id: trim_option(input.profile_id),
        issue_case_id: trim_option(input.issue_case_id),
        duration_ms: input.duration_ms,
        operation_id: trim_option(input.operation_id),
        parent_operation_id: trim_option(input.parent_operation_id),
    }
}

pub(crate) fn event_record_from_input(
    id: String,
    timestamp: String,
    input: SanitizedDiagnosticEventInput,
) -> DiagnosticEventRecord {
    DiagnosticEventRecord {
        id,
        timestamp,
        level: input.level,
        category: input.category,
        source: input.source,
        message: input.message,
        details_json: input.details_json,
        privacy: input.privacy,
        job_id: input.job_id,
        command_id: input.command_id,
        profile_id: input.profile_id,
        issue_case_id: input.issue_case_id,
        duration_ms: input.duration_ms,
        operation_id: input.operation_id,
        parent_operation_id: input.parent_operation_id,
    }
}

pub(crate) fn bootstrap_environment_details(
    app_support_path: &str,
    database_path: &str,
    toolchain_status: &ToolchainStatus,
    database_schema_version: i64,
) -> String {
    json!({
        "cpu_architecture": std::env::consts::ARCH,
        "operating_system": std::env::consts::OS,
        "app_support_path_category": path_category(Some(app_support_path)),
        "database_path_category": path_category(Some(database_path)),
        "argyll_path_category": path_category(toolchain_status.resolved_install_path.as_deref()),
        "argyll_version": toolchain_status.argyll_version.clone().unwrap_or_else(|| "Unknown".to_string()),
        "database_schema_version": database_schema_version
    })
    .to_string()
}

pub(crate) fn retention_status(
    event_count: u32,
    estimated_storage_bytes: u64,
    last_pruned_at: Option<String>,
) -> DiagnosticsRetentionStatus {
    DiagnosticsRetentionStatus {
        retained_days: DEFAULT_RETENTION_DAYS,
        max_storage_mb: DEFAULT_MAX_STORAGE_MB,
        max_payload_bytes: MAX_DIAGNOSTIC_DETAILS_BYTES as u32,
        event_count,
        estimated_storage_bytes,
        last_pruned_at,
    }
}

pub(crate) fn path_category(path: Option<&str>) -> String {
    let Some(path) = path else {
        return "not_resolved".to_string();
    };

    if path.starts_with("/Applications/") {
        "applications".to_string()
    } else if path.starts_with("/opt/homebrew/") || path.starts_with("/usr/local/") {
        "system_toolchain".to_string()
    } else if path.starts_with("/Users/") {
        "user_home".to_string()
    } else if path.starts_with("/tmp/") || path.starts_with("/var/folders/") {
        "temporary".to_string()
    } else {
        "other".to_string()
    }
}

pub(crate) fn export_readme(
    included_events: u32,
    included_transcripts: u32,
    redacted_paths: u32,
) -> String {
    format!(
        "# ArgyllUX Diagnostics Bundle\n\nThis bundle contains privacy-redacted diagnostics for a support or GitHub issue report.\n\nIncluded diagnostic events: {included_events}\nIncluded CLI transcripts: {included_transcripts}\nRedacted path values: {redacted_paths}\n\nBy default, full command output and local private paths are excluded. If CLI transcripts are present, the user explicitly included them during export.\n"
    )
}

pub(crate) fn write_json_file(path: &Path, value: &Value) -> EngineResult<()> {
    let body = serde_json::to_string_pretty(value)?;
    std::fs::write(path, body)?;
    Ok(())
}

pub(crate) fn diagnostic_id() -> String {
    format!("diag-{}", chrono::Utc::now().timestamp_nanos_opt().unwrap_or_default())
}

pub(crate) fn now_timestamp() -> String {
    iso_timestamp()
}

fn sanitize_json_value(value: &mut Value) -> bool {
    match value {
        Value::Object(map) => sanitize_object(map),
        Value::Array(values) => values.iter_mut().fold(false, |changed, item| {
            sanitize_json_value(item) || changed
        }),
        Value::String(text) => {
            if looks_like_private_path(text) {
                *text = redact_path(text);
                true
            } else {
                false
            }
        }
        Value::Null | Value::Bool(_) | Value::Number(_) => false,
    }
}

fn sanitize_object(map: &mut Map<String, Value>) -> bool {
    let mut changed = false;
    let keys = map.keys().cloned().collect::<Vec<_>>();

    for key in keys {
        let lowered = key.to_ascii_lowercase();
        if PRIVATE_VALUE_KEYS.iter().any(|private| lowered.contains(private)) {
            map.insert(key, Value::String("[redacted]".to_string()));
            changed = true;
            continue;
        }

        if PATH_KEYS.iter().any(|path_key| lowered.contains(path_key)) {
            if let Some(Value::String(path)) = map.get_mut(&key) {
                *path = redact_path(path);
                changed = true;
            }
            continue;
        }

        if lowered == "argv" {
            if let Some(argv) = map.get_mut(&key) {
                sanitize_argv(argv);
                changed = true;
            }
            continue;
        }

        if let Some(value) = map.get_mut(&key) {
            changed = sanitize_json_value(value) || changed;
        }
    }

    changed
}

fn sanitize_argv(value: &mut Value) {
    if let Value::Array(items) = value {
        for item in items {
            if let Value::String(text) = item {
                if looks_like_private_path(text) {
                    *text = redact_path(text);
                } else if let Some(file_name) = Path::new(text).file_name().and_then(|name| name.to_str()) {
                    if text.starts_with("/Applications/") || text.starts_with("/opt/homebrew/") || text.starts_with("/usr/local/") {
                        *text = file_name.to_string();
                    }
                }
            }
        }
    }
}

fn looks_like_private_path(value: &str) -> bool {
    value.starts_with("/Users/") || value.starts_with("/private/var/") || value.starts_with("/var/folders/")
}

fn redact_path(path: &str) -> String {
    let file_name = Path::new(path)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("path");

    if path.starts_with("/Users/") {
        format!("$HOME/.../{file_name}")
    } else if path.starts_with("/var/folders/") || path.starts_with("/private/var/") {
        format!("$TEMP/.../{file_name}")
    } else if path.starts_with("/Applications/") {
        format!("/Applications/.../{file_name}")
    } else {
        file_name.to_string()
    }
}

fn truncate_details_json(details: &Value) -> String {
    let mut wrapper = json!({
        "truncated": true,
        "reason": "diagnostic details exceeded the 64 KB payload limit after sanitization"
    });

    if let Value::Object(original) = details {
        if let Some(Value::String(kind)) = original.get("kind") {
            wrapper["kind"] = Value::String(kind.clone());
        }
    }

    serde_json::to_string(&wrapper).unwrap_or_else(|_| "{\"truncated\":true}".to_string())
}

fn trim_or_fallback(value: &str, fallback: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        fallback.to_string()
    } else {
        trimmed.to_string()
    }
}

fn trim_option(value: Option<String>) -> Option<String> {
    value.and_then(|item| {
        let trimmed = item.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_string())
        }
    })
}
```

In `rust/engine/src/lib.rs`, add the module and export imports:

```rust
mod diagnostics;
```

Update the `pub use model::{ ... }` list to include:

```rust
DiagnosticCategory, DiagnosticEventFilter, DiagnosticEventInput, DiagnosticEventRecord,
DiagnosticLevel, DiagnosticPrivacy, DiagnosticsExportOptions, DiagnosticsExportResult,
DiagnosticsRetentionStatus, DiagnosticsSummary,
```

- [ ] **Step 5: Run sanitizer tests and commit**

Run:

```bash
cargo test -p argyllux_engine diagnostics::tests -- --nocapture
```

Expected: PASS.

Commit:

```bash
git add rust/engine/src/model.rs rust/engine/src/diagnostics.rs rust/engine/src/lib.rs
git commit -m "feat: add diagnostic event model and sanitizer"
```

---

### Task 2: SQLite Diagnostics Store, Queries, Summary, And Retention

**Files:**
- Modify: `rust/engine/src/db.rs`
- Test: `rust/engine/src/db.rs`

- [ ] **Step 1: Write failing database tests**

Add these tests inside `#[cfg(test)] mod tests` in `rust/engine/src/db.rs`:

```rust
#[test]
fn diagnostic_events_are_persisted_sanitized_and_filterable() {
    let temp = tempdir().unwrap();
    let config = build_config(temp.path());
    std::fs::create_dir_all(temp.path().join("app-support")).unwrap();
    initialize_database(&config).unwrap();

    let record = record_diagnostic_event(
        &config.database_path,
        &DiagnosticEventInput {
            level: DiagnosticLevel::Error,
            category: DiagnosticCategory::Cli,
            source: "engine.cli".to_string(),
            message: "Command failed.".to_string(),
            details_json: serde_json::json!({
                "argv": ["/opt/homebrew/bin/targen", "-v", "/Users/tylermiller/job/private"],
                "stderr": "private output"
            })
            .to_string(),
            privacy: DiagnosticPrivacy::Internal,
            job_id: Some("job-1".to_string()),
            command_id: Some("command-1".to_string()),
            profile_id: None,
            issue_case_id: None,
            duration_ms: Some(1200),
            operation_id: Some("op-1".to_string()),
            parent_operation_id: None,
        },
    )
    .unwrap();

    assert_eq!(record.level, DiagnosticLevel::Error);
    assert_eq!(record.privacy, DiagnosticPrivacy::SensitiveRedacted);
    assert!(record.details_json.contains("$HOME/.../private"));
    assert!(record.details_json.contains("\"stderr\":\"[redacted]\""));

    let events = list_diagnostic_events(
        &config.database_path,
        &DiagnosticEventFilter {
            levels: vec![DiagnosticLevel::Error],
            categories: vec![DiagnosticCategory::Cli],
            search_text: Some("command".to_string()),
            job_id: Some("job-1".to_string()),
            profile_id: None,
            since_timestamp: None,
            until_timestamp: None,
            errors_only: false,
            limit: 50,
        },
    )
    .unwrap();

    assert_eq!(events.len(), 1);
    assert_eq!(events[0].id, record.id);
}

#[test]
fn diagnostics_summary_counts_warning_error_and_critical_events() {
    let temp = tempdir().unwrap();
    let config = build_config(temp.path());
    std::fs::create_dir_all(temp.path().join("app-support")).unwrap();
    initialize_database(&config).unwrap();

    for (level, message) in [
        (DiagnosticLevel::Info, "Bootstrap complete"),
        (DiagnosticLevel::Warning, "Toolchain partial"),
        (DiagnosticLevel::Error, "Database write failed"),
        (DiagnosticLevel::Critical, "Diagnostics unavailable"),
    ] {
        record_diagnostic_event(
            &config.database_path,
            &DiagnosticEventInput {
                level,
                category: DiagnosticCategory::Engine,
                source: "engine.test".to_string(),
                message: message.to_string(),
                details_json: "{}".to_string(),
                privacy: DiagnosticPrivacy::Public,
                job_id: None,
                command_id: None,
                profile_id: None,
                issue_case_id: None,
                duration_ms: None,
                operation_id: None,
                parent_operation_id: None,
            },
        )
        .unwrap();
    }

    let summary = get_diagnostics_summary(
        &config.database_path,
        "Ready",
        "3.5.0",
        "system_toolchain",
    )
    .unwrap();

    assert_eq!(summary.total_count, 4);
    assert_eq!(summary.warning_count, 1);
    assert_eq!(summary.error_count, 1);
    assert_eq!(summary.critical_count, 1);
    assert_eq!(summary.latest_critical_message.as_deref(), Some("Diagnostics unavailable"));
    assert_eq!(summary.argyll_version, "3.5.0");
}

#[test]
fn retention_prunes_events_older_than_retention_window() {
    let temp = tempdir().unwrap();
    let config = build_config(temp.path());
    std::fs::create_dir_all(temp.path().join("app-support")).unwrap();
    initialize_database(&config).unwrap();

    let connection = open_connection(&config.database_path).unwrap();
    connection
        .execute(
            r#"
            INSERT INTO diagnostic_events (
                id, timestamp, level, category, source, message, details_json, privacy,
                job_id, command_id, profile_id, issue_case_id, duration_ms, operation_id, parent_operation_id
            )
            VALUES (?1, ?2, 'info', 'engine', 'engine.test', 'old', '{}', 'public',
                NULL, NULL, NULL, NULL, NULL, NULL, NULL)
            "#,
            params!["diag-old", "2020-01-01T00:00:00Z"],
        )
        .unwrap();

    record_diagnostic_event(
        &config.database_path,
        &DiagnosticEventInput {
            level: DiagnosticLevel::Info,
            category: DiagnosticCategory::Engine,
            source: "engine.test".to_string(),
            message: "new".to_string(),
            details_json: "{}".to_string(),
            privacy: DiagnosticPrivacy::Public,
            job_id: None,
            command_id: None,
            profile_id: None,
            issue_case_id: None,
            duration_ms: None,
            operation_id: None,
            parent_operation_id: None,
        },
    )
    .unwrap();

    let pruned = prune_diagnostic_events(&config.database_path).unwrap();
    assert_eq!(pruned, 1);

    let events = list_diagnostic_events(
        &config.database_path,
        &DiagnosticEventFilter {
            levels: Vec::new(),
            categories: Vec::new(),
            search_text: None,
            job_id: None,
            profile_id: None,
            since_timestamp: None,
            until_timestamp: None,
            errors_only: false,
            limit: 50,
        },
    )
    .unwrap();

    assert_eq!(events.len(), 1);
    assert_eq!(events[0].message, "new");
}
```

Also add these imports to the test module:

```rust
use crate::model::{
    DiagnosticCategory, DiagnosticEventFilter, DiagnosticEventInput, DiagnosticLevel,
    DiagnosticPrivacy,
};
```

- [ ] **Step 2: Run database tests to verify failure**

Run:

```bash
cargo test -p argyllux_engine db::tests::diagnostic -- --nocapture
```

Expected: FAIL because the diagnostic store functions and table do not exist.

- [ ] **Step 3: Add table, indexes, and encoders**

In `rust/engine/src/db.rs`, update the imports:

```rust
use crate::diagnostics;
use crate::model::{
    ActiveWorkItem, ArtifactKind, ColorantFamily, CommandRunState, CommandStream,
    CreateNewProfileDraftInput, CreatePaperInput, CreatePrinterInput,
    CreatePrinterPaperPresetInput, DashboardSnapshot, DeleteResult, DiagnosticCategory,
    DiagnosticEventFilter, DiagnosticEventInput, DiagnosticEventRecord, DiagnosticLevel,
    DiagnosticPrivacy, DiagnosticsSummary, EngineConfig, InstrumentStatus, JobArtifactRecord,
    JobCommandEventRecord, JobCommandRecord, MeasurementMode, MeasurementStatusRecord,
    NewProfileContextRecord, PaperRecord, PaperThicknessUnit, PaperWeightUnit,
    PrintSettingsRecord, PrinterPaperPresetRecord, PrinterProfileRecord, PrinterRecord,
    ReviewSummaryRecord, SaveNewProfileContextInput, SavePrintSettingsInput,
    SaveTargetSettingsInput, StartMeasurementInput, TargetSettingsRecord, ToolchainState,
    ToolchainStatus, UpdatePaperInput, UpdatePrinterInput, UpdatePrinterPaperPresetInput,
    WorkflowStage, WorkflowStageState, WorkflowStageSummary,
};
```

Change:

```rust
const DATABASE_VERSION: i64 = 5;
```

to:

```rust
pub(crate) const DATABASE_VERSION: i64 = 6;
```

Inside `create_latest_schema`, after `job_command_events`, add:

```rust
        CREATE TABLE IF NOT EXISTS diagnostic_events (
            id TEXT PRIMARY KEY,
            timestamp TEXT NOT NULL,
            level TEXT NOT NULL,
            category TEXT NOT NULL,
            source TEXT NOT NULL,
            message TEXT NOT NULL,
            details_json TEXT NOT NULL,
            privacy TEXT NOT NULL,
            job_id TEXT,
            command_id TEXT,
            profile_id TEXT,
            issue_case_id TEXT,
            duration_ms INTEGER,
            operation_id TEXT,
            parent_operation_id TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_diagnostic_events_timestamp
            ON diagnostic_events(timestamp DESC);

        CREATE INDEX IF NOT EXISTS idx_diagnostic_events_level
            ON diagnostic_events(level);

        CREATE INDEX IF NOT EXISTS idx_diagnostic_events_category
            ON diagnostic_events(category);

        CREATE INDEX IF NOT EXISTS idx_diagnostic_events_job_id
            ON diagnostic_events(job_id);

        CREATE INDEX IF NOT EXISTS idx_diagnostic_events_command_id
            ON diagnostic_events(command_id);
```

Add these encoder/decoder helpers near the existing command encoders:

```rust
fn encode_diagnostic_level(level: &DiagnosticLevel) -> &'static str {
    match level {
        DiagnosticLevel::Debug => "debug",
        DiagnosticLevel::Info => "info",
        DiagnosticLevel::Warning => "warning",
        DiagnosticLevel::Error => "error",
        DiagnosticLevel::Critical => "critical",
    }
}

fn decode_diagnostic_level(value: &str) -> DiagnosticLevel {
    match value {
        "debug" => DiagnosticLevel::Debug,
        "warning" => DiagnosticLevel::Warning,
        "error" => DiagnosticLevel::Error,
        "critical" => DiagnosticLevel::Critical,
        _ => DiagnosticLevel::Info,
    }
}

fn encode_diagnostic_category(category: &DiagnosticCategory) -> &'static str {
    match category {
        DiagnosticCategory::App => "app",
        DiagnosticCategory::Ui => "ui",
        DiagnosticCategory::Workflow => "workflow",
        DiagnosticCategory::Engine => "engine",
        DiagnosticCategory::Cli => "cli",
        DiagnosticCategory::Database => "database",
        DiagnosticCategory::Toolchain => "toolchain",
        DiagnosticCategory::Performance => "performance",
        DiagnosticCategory::Environment => "environment",
    }
}

fn decode_diagnostic_category(value: &str) -> DiagnosticCategory {
    match value {
        "app" => DiagnosticCategory::App,
        "ui" => DiagnosticCategory::Ui,
        "workflow" => DiagnosticCategory::Workflow,
        "cli" => DiagnosticCategory::Cli,
        "database" => DiagnosticCategory::Database,
        "toolchain" => DiagnosticCategory::Toolchain,
        "performance" => DiagnosticCategory::Performance,
        "environment" => DiagnosticCategory::Environment,
        _ => DiagnosticCategory::Engine,
    }
}

fn encode_diagnostic_privacy(privacy: &DiagnosticPrivacy) -> &'static str {
    match privacy {
        DiagnosticPrivacy::Public => "public",
        DiagnosticPrivacy::Internal => "internal",
        DiagnosticPrivacy::SensitiveRedacted => "sensitive_redacted",
    }
}

fn decode_diagnostic_privacy(value: &str) -> DiagnosticPrivacy {
    match value {
        "internal" => DiagnosticPrivacy::Internal,
        "sensitive_redacted" => DiagnosticPrivacy::SensitiveRedacted,
        _ => DiagnosticPrivacy::Public,
    }
}
```

- [ ] **Step 4: Add persistence, filtering, summary, and pruning functions**

In `rust/engine/src/db.rs`, add these public functions near the toolchain functions:

```rust
pub fn record_diagnostic_event(
    database_path: &str,
    input: &DiagnosticEventInput,
) -> EngineResult<DiagnosticEventRecord> {
    let connection = open_connection(database_path)?;
    let sanitized = diagnostics::sanitize_event_input(input.clone());
    let id = diagnostics::diagnostic_id();
    let timestamp = diagnostics::now_timestamp();

    connection.execute(
        r#"
        INSERT INTO diagnostic_events (
            id, timestamp, level, category, source, message, details_json, privacy,
            job_id, command_id, profile_id, issue_case_id, duration_ms, operation_id, parent_operation_id
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)
        "#,
        params![
            &id,
            &timestamp,
            encode_diagnostic_level(&sanitized.level),
            encode_diagnostic_category(&sanitized.category),
            &sanitized.source,
            &sanitized.message,
            &sanitized.details_json,
            encode_diagnostic_privacy(&sanitized.privacy),
            &sanitized.job_id,
            &sanitized.command_id,
            &sanitized.profile_id,
            &sanitized.issue_case_id,
            sanitized.duration_ms,
            &sanitized.operation_id,
            &sanitized.parent_operation_id,
        ],
    )?;

    Ok(diagnostics::event_record_from_input(id, timestamp, sanitized))
}

pub fn list_diagnostic_events(
    database_path: &str,
    filter: &DiagnosticEventFilter,
) -> EngineResult<Vec<DiagnosticEventRecord>> {
    let connection = open_connection(database_path)?;
    let limit = filter.limit.clamp(1, 500);
    let rows = connection
        .prepare(
            r#"
            SELECT id, timestamp, level, category, source, message, details_json, privacy,
                   job_id, command_id, profile_id, issue_case_id, duration_ms, operation_id, parent_operation_id
            FROM diagnostic_events
            ORDER BY timestamp DESC
            LIMIT ?1
            "#,
        )?
        .query_map(params![limit], diagnostic_event_from_row)?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(rows
        .into_iter()
        .filter(|event| diagnostic_event_matches_filter(event, filter))
        .collect())
}

pub fn get_diagnostics_summary(
    database_path: &str,
    app_readiness: &str,
    argyll_version: &str,
    argyll_path_category: &str,
) -> EngineResult<DiagnosticsSummary> {
    let connection = open_connection(database_path)?;
    let total_count = diagnostic_count(&connection, None)?;
    let warning_count = diagnostic_count(&connection, Some("warning"))?;
    let error_count = diagnostic_count(&connection, Some("error"))?;
    let critical_count = diagnostic_count(&connection, Some("critical"))?;
    let latest_critical_message = latest_diagnostic_message(&connection, "critical")?;
    let latest_event_timestamp = latest_diagnostic_timestamp(&connection)?;
    let estimated_storage_bytes = estimate_diagnostic_storage_bytes(&connection)?;

    Ok(DiagnosticsSummary {
        total_count,
        warning_count,
        error_count,
        critical_count,
        latest_critical_message,
        latest_event_timestamp,
        app_readiness: app_readiness.to_string(),
        argyll_version: argyll_version.to_string(),
        argyll_path_category: argyll_path_category.to_string(),
        retention: diagnostics::retention_status(total_count, estimated_storage_bytes, None),
    })
}

pub fn prune_diagnostic_events(database_path: &str) -> EngineResult<u32> {
    let connection = open_connection(database_path)?;
    let cutoff = (Utc::now() - Duration::days(diagnostics::DEFAULT_RETENTION_DAYS as i64))
        .to_rfc3339();
    let deleted = connection.execute(
        "DELETE FROM diagnostic_events WHERE timestamp < ?1",
        params![cutoff],
    )?;
    Ok(deleted as u32)
}
```

Add these private helpers near the new functions:

```rust
fn diagnostic_event_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<DiagnosticEventRecord> {
    Ok(DiagnosticEventRecord {
        id: row.get(0)?,
        timestamp: row.get(1)?,
        level: decode_diagnostic_level(&row.get::<_, String>(2)?),
        category: decode_diagnostic_category(&row.get::<_, String>(3)?),
        source: row.get(4)?,
        message: row.get(5)?,
        details_json: row.get(6)?,
        privacy: decode_diagnostic_privacy(&row.get::<_, String>(7)?),
        job_id: row.get(8)?,
        command_id: row.get(9)?,
        profile_id: row.get(10)?,
        issue_case_id: row.get(11)?,
        duration_ms: row.get(12)?,
        operation_id: row.get(13)?,
        parent_operation_id: row.get(14)?,
    })
}

fn diagnostic_event_matches_filter(
    event: &DiagnosticEventRecord,
    filter: &DiagnosticEventFilter,
) -> bool {
    if filter.errors_only
        && !matches!(
            event.level,
            DiagnosticLevel::Error | DiagnosticLevel::Critical
        )
    {
        return false;
    }

    if !filter.levels.is_empty() && !filter.levels.contains(&event.level) {
        return false;
    }

    if !filter.categories.is_empty() && !filter.categories.contains(&event.category) {
        return false;
    }

    if let Some(job_id) = filter.job_id.as_deref()
        && event.job_id.as_deref() != Some(job_id)
    {
        return false;
    }

    if let Some(profile_id) = filter.profile_id.as_deref()
        && event.profile_id.as_deref() != Some(profile_id)
    {
        return false;
    }

    if let Some(since) = filter.since_timestamp.as_deref()
        && event.timestamp.as_str() < since
    {
        return false;
    }

    if let Some(until) = filter.until_timestamp.as_deref()
        && event.timestamp.as_str() > until
    {
        return false;
    }

    if let Some(search_text) = filter.search_text.as_deref() {
        let needle = search_text.trim().to_ascii_lowercase();
        if !needle.is_empty() {
            let haystack = format!(
                "{} {} {} {}",
                event.source, event.message, event.details_json, event.timestamp
            )
            .to_ascii_lowercase();
            return haystack.contains(&needle);
        }
    }

    true
}

fn diagnostic_count(connection: &Connection, level: Option<&str>) -> EngineResult<u32> {
    let count: i64 = match level {
        Some(level) => connection.query_row(
            "SELECT COUNT(*) FROM diagnostic_events WHERE level = ?1",
            params![level],
            |row| row.get(0),
        )?,
        None => connection.query_row("SELECT COUNT(*) FROM diagnostic_events", [], |row| row.get(0))?,
    };
    Ok(count as u32)
}

fn latest_diagnostic_message(connection: &Connection, level: &str) -> EngineResult<Option<String>> {
    connection
        .query_row(
            "SELECT message FROM diagnostic_events WHERE level = ?1 ORDER BY timestamp DESC LIMIT 1",
            params![level],
            |row| row.get(0),
        )
        .optional()
        .map_err(Into::into)
}

fn latest_diagnostic_timestamp(connection: &Connection) -> EngineResult<Option<String>> {
    connection
        .query_row(
            "SELECT timestamp FROM diagnostic_events ORDER BY timestamp DESC LIMIT 1",
            [],
            |row| row.get(0),
        )
        .optional()
        .map_err(Into::into)
}

fn estimate_diagnostic_storage_bytes(connection: &Connection) -> EngineResult<u64> {
    let bytes: Option<i64> = connection.query_row(
        r#"
        SELECT SUM(
            LENGTH(id) + LENGTH(timestamp) + LENGTH(level) + LENGTH(category) +
            LENGTH(source) + LENGTH(message) + LENGTH(details_json) + LENGTH(privacy) +
            COALESCE(LENGTH(job_id), 0) + COALESCE(LENGTH(command_id), 0) +
            COALESCE(LENGTH(profile_id), 0) + COALESCE(LENGTH(issue_case_id), 0) +
            COALESCE(LENGTH(operation_id), 0) + COALESCE(LENGTH(parent_operation_id), 0)
        )
        FROM diagnostic_events
        "#,
        [],
        |row| row.get(0),
    )?;
    Ok(bytes.unwrap_or(0).max(0) as u64)
}
```

- [ ] **Step 5: Run database tests and commit**

Run:

```bash
cargo test -p argyllux_engine db::tests::diagnostic -- --nocapture
```

Expected: PASS.

Commit:

```bash
git add rust/engine/src/db.rs
git commit -m "feat: persist and query diagnostic events"
```

---

### Task 3: Engine Bridge Methods And Bootstrap Diagnostics

**Files:**
- Modify: `rust/engine/src/lib.rs`
- Modify: `rust/engine/src/logging.rs`
- Modify: `apple/ArgyllUX/Sources/Models/EngineBridge.swift`
- Modify generated after command: `apple/ArgyllUX/Bridge/Generated/argyllux.swift`
- Modify generated after command: `apple/ArgyllUX/Bridge/Generated/argylluxFFI.h`
- Modify generated after command: `apple/ArgyllUX/Bridge/Generated/argylluxFFI.modulemap`
- Modify generated after command: `apple/ArgyllUX/Bridge/Generated/libargyllux_engine.a`
- Test: `rust/engine/src/lib.rs`

- [ ] **Step 1: Write failing bridge tests**

Add this test inside `#[cfg(test)] mod tests` in `rust/engine/src/lib.rs`:

```rust
#[test]
fn bridge_records_lists_and_summarizes_diagnostic_events() {
    let temp = tempfile::tempdir().unwrap();
    let engine = Engine::new();
    let config = EngineConfig {
        app_support_path: temp.path().join("app-support").to_string_lossy().to_string(),
        database_path: temp.path().join("app-support/argyllux.sqlite").to_string_lossy().to_string(),
        log_path: temp.path().join("logs/engine.log").to_string_lossy().to_string(),
        argyll_override_path: None,
        additional_search_roots: Vec::new(),
    };

    engine.bootstrap(config);
    let record = engine.record_diagnostic_event(DiagnosticEventInput {
        level: DiagnosticLevel::Warning,
        category: DiagnosticCategory::Ui,
        source: "swift.workflow.new_profile".to_string(),
        message: "User started New Profile.".to_string(),
        details_json: serde_json::json!({ "action": "new_profile" }).to_string(),
        privacy: DiagnosticPrivacy::Public,
        job_id: Some("job-1".to_string()),
        command_id: None,
        profile_id: None,
        issue_case_id: None,
        duration_ms: None,
        operation_id: None,
        parent_operation_id: None,
    });

    assert_eq!(record.category, DiagnosticCategory::Ui);

    let events = engine.list_diagnostic_events(DiagnosticEventFilter {
        levels: vec![DiagnosticLevel::Warning],
        categories: vec![DiagnosticCategory::Ui],
        search_text: Some("New Profile".to_string()),
        job_id: Some("job-1".to_string()),
        profile_id: None,
        since_timestamp: None,
        until_timestamp: None,
        errors_only: false,
        limit: 50,
    });

    assert_eq!(events.len(), 1);
    assert_eq!(events[0].message, "User started New Profile.");

    let summary = engine.get_diagnostics_summary();
    assert!(summary.total_count >= 1);
    assert_eq!(summary.warning_count, 1);
}
```

- [ ] **Step 2: Run bridge test to verify failure**

Run:

```bash
cargo test -p argyllux_engine lib::tests::bridge_records_lists_and_summarizes_diagnostic_events -- --nocapture
```

Expected: FAIL because `Engine` does not export diagnostic bridge methods.

- [ ] **Step 3: Add exported engine methods**

In `rust/engine/src/lib.rs`, add these methods inside `impl Engine` after `get_recent_logs`:

```rust
    #[uniffi::method(name = "recordDiagnosticEvent")]
    pub fn record_diagnostic_event(&self, input: DiagnosticEventInput) -> DiagnosticEventRecord {
        match with_config(&self.state, |config| {
            db::record_diagnostic_event(&config.database_path, &input)
        }) {
            Ok(record) => record,
            Err(error) => fallback_diagnostic_event(input, error.to_string()),
        }
    }

    #[uniffi::method(name = "listDiagnosticEvents")]
    pub fn list_diagnostic_events(&self, filter: DiagnosticEventFilter) -> Vec<DiagnosticEventRecord> {
        match with_config(&self.state, |config| {
            db::list_diagnostic_events(&config.database_path, &filter)
        }) {
            Ok(events) => events,
            Err(error) => vec![fallback_diagnostic_event(
                DiagnosticEventInput {
                    level: DiagnosticLevel::Error,
                    category: DiagnosticCategory::Database,
                    source: "engine.diagnostics".to_string(),
                    message: format!("Listing diagnostics failed: {error}"),
                    details_json: "{}".to_string(),
                    privacy: DiagnosticPrivacy::Public,
                    job_id: None,
                    command_id: None,
                    profile_id: None,
                    issue_case_id: None,
                    duration_ms: None,
                    operation_id: None,
                    parent_operation_id: None,
                },
                error.to_string(),
            )],
        }
    }

    #[uniffi::method(name = "getDiagnosticsSummary")]
    pub fn get_diagnostics_summary(&self) -> DiagnosticsSummary {
        let state = self.state.read().expect("engine state lock poisoned");
        let Some(config) = state.config.clone() else {
            return fallback_diagnostics_summary("Blocked", "Unknown", "not_resolved");
        };
        let readiness = readiness_label(&state.app_health.readiness);
        let argyll_version = state
            .toolchain_status
            .argyll_version
            .clone()
            .unwrap_or_else(|| "Unknown".to_string());
        let argyll_path_category = diagnostics::path_category(
            state.toolchain_status.resolved_install_path.as_deref(),
        );
        drop(state);

        db::get_diagnostics_summary(
            &config.database_path,
            &readiness,
            &argyll_version,
            &argyll_path_category,
        )
        .unwrap_or_else(|_| fallback_diagnostics_summary(&readiness, &argyll_version, &argyll_path_category))
    }
```

Add these fallback helpers near the existing fallback functions:

```rust
fn fallback_diagnostic_event(input: DiagnosticEventInput, error: String) -> DiagnosticEventRecord {
    DiagnosticEventRecord {
        id: "diagnostics-unavailable".to_string(),
        timestamp: crate::support::iso_timestamp(),
        level: DiagnosticLevel::Error,
        category: DiagnosticCategory::Database,
        source: "engine.diagnostics".to_string(),
        message: format!("Diagnostics store unavailable: {error}"),
        details_json: "{}".to_string(),
        privacy: DiagnosticPrivacy::Public,
        job_id: input.job_id,
        command_id: input.command_id,
        profile_id: input.profile_id,
        issue_case_id: input.issue_case_id,
        duration_ms: input.duration_ms,
        operation_id: input.operation_id,
        parent_operation_id: input.parent_operation_id,
    }
}

fn fallback_diagnostics_summary(
    readiness: &str,
    argyll_version: &str,
    argyll_path_category: &str,
) -> DiagnosticsSummary {
    DiagnosticsSummary {
        total_count: 0,
        warning_count: 0,
        error_count: 0,
        critical_count: 0,
        latest_critical_message: None,
        latest_event_timestamp: None,
        app_readiness: readiness.to_string(),
        argyll_version: argyll_version.to_string(),
        argyll_path_category: argyll_path_category.to_string(),
        retention: diagnostics::retention_status(0, 0, None),
    }
}

fn readiness_label(value: &str) -> String {
    match value {
        "ready" => "Ready".to_string(),
        "attention" => "Needs Attention".to_string(),
        "blocked" => "Blocked".to_string(),
        other if other.trim().is_empty() => "Blocked".to_string(),
        other => other.to_string(),
    }
}
```

- [ ] **Step 4: Record bootstrap diagnostics and retention pruning**

In `Engine::bootstrap`, after successful `db::initialize_database`, add:

```rust
                if let Err(error) = db::prune_diagnostic_events(&sanitized_config.database_path) {
                    logging::append_log(
                        &sanitized_config.log_path,
                        "warning",
                        "engine.diagnostics",
                        format!("Diagnostics retention pruning failed: {error}"),
                    );
                }
```

After `let toolchain_status = toolchain::discover_toolchain(&sanitized_config);`, add:

```rust
        if database_initialized {
            let _ = db::record_diagnostic_event(
                &sanitized_config.database_path,
                &DiagnosticEventInput {
                    level: DiagnosticLevel::Info,
                    category: DiagnosticCategory::Environment,
                    source: "engine.bootstrap".to_string(),
                    message: "ArgyllUX bootstrap environment captured.".to_string(),
                    details_json: diagnostics::bootstrap_environment_details(
                        &sanitized_config.app_support_path,
                        &sanitized_config.database_path,
                        &toolchain_status,
                        db::DATABASE_VERSION,
                    ),
                    privacy: DiagnosticPrivacy::SensitiveRedacted,
                    job_id: None,
                    command_id: None,
                    profile_id: None,
                    issue_case_id: None,
                    duration_ms: None,
                    operation_id: Some("engine.bootstrap".to_string()),
                    parent_operation_id: None,
                },
            );
        }
```

Update `log_config_error` to also record a diagnostic event:

```rust
fn log_config_error(state: &RwLock<EngineState>, source: &str, message: &str) {
    if let Some(config) = state
        .read()
        .expect("engine state lock poisoned")
        .config
        .clone()
    {
        logging::append_log(&config.log_path, "error", source, message.to_string());
        let _ = db::record_diagnostic_event(
            &config.database_path,
            &DiagnosticEventInput {
                level: DiagnosticLevel::Error,
                category: DiagnosticCategory::Engine,
                source: source.to_string(),
                message: message.to_string(),
                details_json: "{}".to_string(),
                privacy: DiagnosticPrivacy::Public,
                job_id: None,
                command_id: None,
                profile_id: None,
                issue_case_id: None,
                duration_ms: None,
                operation_id: None,
                parent_operation_id: None,
            },
        );
    }
}
```

At the top of `rust/engine/src/logging.rs`, add:

```rust
//! Compatibility writer for newline-delimited `engine.log`.
//!
//! New diagnostics features should persist structured events through the
//! SQLite diagnostics store. This file remains for transitional debug output
//! and local support visibility.
```

- [ ] **Step 5: Run Rust bridge tests**

Run:

```bash
cargo test -p argyllux_engine lib::tests::bridge_records_lists_and_summarizes_diagnostic_events -- --nocapture
```

Expected: PASS.

- [ ] **Step 6: Regenerate the Swift bridge**

Run:

```bash
scripts/build-swift-bridge.sh
```

Expected: PASS and generated files under `apple/ArgyllUX/Bridge/Generated/` change. Do not hand-edit generated files.

- [ ] **Step 7: Add Swift actor wrappers**

In `apple/ArgyllUX/Sources/Models/EngineBridge.swift`, add these methods after `getRecentLogs`:

```swift
    func recordDiagnosticEvent(input: DiagnosticEventInput) -> DiagnosticEventRecord {
        engine.recordDiagnosticEvent(input: input)
    }

    func listDiagnosticEvents(filter: DiagnosticEventFilter) -> [DiagnosticEventRecord] {
        engine.listDiagnosticEvents(filter: filter)
    }

    func getDiagnosticsSummary() -> DiagnosticsSummary {
        engine.getDiagnosticsSummary()
    }
```

- [ ] **Step 8: Run bridge build check and commit**

Run:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx -derivedDataPath /tmp/ArgyllUXDerivedData build
```

Expected: PASS.

Commit:

```bash
git add rust/engine/src/lib.rs rust/engine/src/logging.rs apple/ArgyllUX/Sources/Models/EngineBridge.swift apple/ArgyllUX/Bridge/Generated/argyllux.swift apple/ArgyllUX/Bridge/Generated/argylluxFFI.h apple/ArgyllUX/Bridge/Generated/argylluxFFI.modulemap apple/ArgyllUX/Bridge/Generated/libargyllux_engine.a
git commit -m "feat: expose diagnostics over the engine bridge"
```

---

### Task 4: Swift Diagnostics Model

**Files:**
- Create: `apple/ArgyllUX/Sources/Models/Shell/DiagnosticsModel.swift`
- Modify: `apple/ArgyllUX/Sources/Models/AppModel.swift`
- Modify: `apple/ArgyllUXTests/Support/AppModelTestSupport.swift`
- Create: `apple/ArgyllUXTests/DiagnosticsModelTests.swift`

- [ ] **Step 1: Write failing Swift model tests**

Create `apple/ArgyllUXTests/DiagnosticsModelTests.swift`:

```swift
import Foundation
import Testing
@testable import ArgyllUX

@MainActor
struct DiagnosticsModelTests {
    @Test
    func refreshLoadsSummaryAndEvents() async {
        let fakeEngine = FakeEngine()
        fakeEngine.diagnosticsSummaryValue = makeDiagnosticsSummary(total: 3, warnings: 1, errors: 1, critical: 0)
        fakeEngine.diagnosticEventsValue = [
            makeDiagnosticEvent(level: .info, category: .app, message: "Bootstrap complete."),
            makeDiagnosticEvent(level: .warning, category: .toolchain, message: "Toolchain partial."),
            makeDiagnosticEvent(level: .error, category: .database, message: "Database write failed."),
        ]
        let model = DiagnosticsModel(bridge: EngineBridge(engine: fakeEngine))

        await model.refresh()

        #expect(model.summary?.totalCount == 3)
        #expect(model.visibleEvents.map(\.message) == [
            "Bootstrap complete.",
            "Toolchain partial.",
            "Database write failed.",
        ])
        #expect(model.isLoading == false)
    }

    @Test
    func errorsOnlyFilterRequestsErrorAndCriticalEvents() async {
        let fakeEngine = FakeEngine()
        let model = DiagnosticsModel(bridge: EngineBridge(engine: fakeEngine))

        model.errorsOnly = true
        await model.refresh()

        #expect(fakeEngine.lastDiagnosticFilter?.errorsOnly == true)
        #expect(fakeEngine.lastDiagnosticFilter?.limit == 200)
    }

    @Test
    func commandLinkedEventRequestsTranscriptForRelatedJob() {
        let model = DiagnosticsModel(bridge: EngineBridge(engine: FakeEngine()))
        var openedJobID: String?
        model.openCliTranscriptRequested = { openedJobID = $0 }

        model.openCliTranscript(for: makeDiagnosticEvent(
            level: .error,
            category: .cli,
            message: "colprof failed.",
            jobId: "job-1",
            commandId: "command-1"
        ))

        #expect(openedJobID == "job-1")
    }
}
```

- [ ] **Step 2: Run Swift test to verify failure**

Run:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx -derivedDataPath /tmp/ArgyllUXDerivedData test -only-testing:ArgyllUXTests/DiagnosticsModelTests
```

Expected: FAIL because `DiagnosticsModel`, fake diagnostic values, and fake engine diagnostic methods do not exist.

- [ ] **Step 3: Add the Swift diagnostics model**

Create `apple/ArgyllUX/Sources/Models/Shell/DiagnosticsModel.swift`:

```swift
import Foundation

enum DiagnosticsLevelFilter: String, CaseIterable, Identifiable {
    case all
    case debug
    case info
    case warning
    case error
    case critical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Levels"
        case .debug: "Debug"
        case .info: "Info"
        case .warning: "Warnings"
        case .error: "Errors"
        case .critical: "Critical"
        }
    }

    var bridgeLevels: [DiagnosticLevel] {
        switch self {
        case .all:
            []
        case .debug:
            [.debug]
        case .info:
            [.info]
        case .warning:
            [.warning]
        case .error:
            [.error]
        case .critical:
            [.critical]
        }
    }
}

enum DiagnosticsCategoryFilter: String, CaseIterable, Identifiable {
    case all
    case app
    case ui
    case workflow
    case engine
    case cli
    case database
    case toolchain
    case performance
    case environment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Categories"
        case .app: "App"
        case .ui: "UI"
        case .workflow: "Workflow"
        case .engine: "Engine"
        case .cli: "CLI"
        case .database: "Database"
        case .toolchain: "Toolchain"
        case .performance: "Performance"
        case .environment: "Environment"
        }
    }

    var bridgeCategories: [DiagnosticCategory] {
        switch self {
        case .all: []
        case .app: [.app]
        case .ui: [.ui]
        case .workflow: [.workflow]
        case .engine: [.engine]
        case .cli: [.cli]
        case .database: [.database]
        case .toolchain: [.toolchain]
        case .performance: [.performance]
        case .environment: [.environment]
        }
    }
}

@MainActor
final class DiagnosticsModel: ObservableObject {
    @Published private(set) var summary: DiagnosticsSummary?
    @Published private(set) var visibleEvents: [DiagnosticEventRecord] = []
    @Published private(set) var selectedEventID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var exportMessage: String?
    @Published var levelFilter: DiagnosticsLevelFilter = .all
    @Published var categoryFilter: DiagnosticsCategoryFilter = .all
    @Published var searchText = ""
    @Published var errorsOnly = false

    private let bridge: EngineBridge

    var openCliTranscriptRequested: ((String) -> Void)?

    init(bridge: EngineBridge) {
        self.bridge = bridge
    }

    var selectedEvent: DiagnosticEventRecord? {
        guard let selectedEventID else { return nil }
        return visibleEvents.first { $0.id == selectedEventID }
    }

    func refresh(limit: UInt32 = 200) async {
        isLoading = true
        let filter = DiagnosticEventFilter(
            levels: levelFilter.bridgeLevels,
            categories: categoryFilter.bridgeCategories,
            searchText: searchText.trimmed.isEmpty ? nil : searchText.trimmed,
            jobId: nil,
            profileId: nil,
            sinceTimestamp: nil,
            untilTimestamp: nil,
            errorsOnly: errorsOnly,
            limit: limit
        )
        let summary = await bridge.getDiagnosticsSummary()
        let events = await bridge.listDiagnosticEvents(filter: filter)

        self.summary = summary
        visibleEvents = events
        if selectedEventID == nil || !events.contains(where: { $0.id == selectedEventID }) {
            selectedEventID = events.first?.id
        }
        isLoading = false
    }

    func select(_ event: DiagnosticEventRecord) {
        selectedEventID = event.id
    }

    func openCliTranscript(for event: DiagnosticEventRecord) {
        guard event.category == .cli, let jobID = event.jobId else { return }
        openCliTranscriptRequested?(jobID)
    }

    func recordUiEvent(source: String, message: String, details: [String: String] = [:], jobID: String? = nil) async {
        let detailsData = (try? JSONSerialization.data(withJSONObject: details, options: [.sortedKeys])) ?? Data("{}".utf8)
        let detailsJSON = String(data: detailsData, encoding: .utf8) ?? "{}"
        _ = await bridge.recordDiagnosticEvent(input: DiagnosticEventInput(
            level: .info,
            category: .ui,
            source: source,
            message: message,
            detailsJson: detailsJSON,
            privacy: .public,
            jobId: jobID,
            commandId: nil,
            profileId: nil,
            issueCaseId: nil,
            durationMs: nil,
            operationId: nil,
            parentOperationId: nil
        ))
    }

    func clearExportMessage() {
        exportMessage = nil
    }
}
```

- [ ] **Step 4: Wire the model into AppModel**

In `apple/ArgyllUX/Sources/Models/AppModel.swift`, add:

```swift
    let diagnostics: DiagnosticsModel
```

In `init`, after `cliTranscript = ...`, add:

```swift
        diagnostics = DiagnosticsModel(bridge: bridge)
```

In `configureFeatureModels`, add:

```swift
        diagnostics.openCliTranscriptRequested = { [weak self] jobId in
            guard let self else { return }
            Task {
                await self.openCliTranscript(jobId: jobId)
            }
        }
```

In `observeFeatureModels`, add:

```swift
        observe(diagnostics)
```

In `openNewProfileWorkflow`, before `await workflow.openNewProfileWorkflow(...)`, add:

```swift
        await diagnostics.recordUiEvent(
            source: "swift.workflow.new_profile",
            message: "User opened New Profile.",
            details: ["entry_point": "app_shell"]
        )
```

In the failed deletion branches of `performPendingDeletion`, after setting `deletionError`, add this for active work:

```swift
                    await self.diagnostics.recordUiEvent(
                        source: "swift.active_work.delete",
                        message: "Active Work deletion failed.",
                        details: ["result": "failed"],
                        jobID: jobId
                    )
```

For the printer profile failure branch, add:

```swift
                    await self.diagnostics.recordUiEvent(
                        source: "swift.printer_profiles.delete",
                        message: "Printer Profile deletion failed.",
                        details: ["result": "failed"]
                    )
```

- [ ] **Step 5: Extend FakeEngine and test helpers**

In `apple/ArgyllUXTests/Support/AppModelTestSupport.swift`, add properties to `FakeEngine`:

```swift
    private(set) var recordedDiagnosticInputs: [DiagnosticEventInput] = []
    private(set) var lastDiagnosticFilter: DiagnosticEventFilter?
    var diagnosticEventsValue: [DiagnosticEventRecord] = []
    var diagnosticsSummaryValue = makeDiagnosticsSummary()
```

Add protocol methods to `FakeEngine`:

```swift
    func recordDiagnosticEvent(input: DiagnosticEventInput) -> DiagnosticEventRecord {
        recordedDiagnosticInputs.append(input)
        let record = makeDiagnosticEvent(
            level: input.level,
            category: input.category,
            message: input.message,
            jobId: input.jobId,
            commandId: input.commandId
        )
        diagnosticEventsValue.insert(record, at: 0)
        return record
    }

    func listDiagnosticEvents(filter: DiagnosticEventFilter) -> [DiagnosticEventRecord] {
        lastDiagnosticFilter = filter
        return diagnosticEventsValue
    }

    func getDiagnosticsSummary() -> DiagnosticsSummary {
        diagnosticsSummaryValue
    }
```

Add helper functions near the other test factories:

```swift
func makeDiagnosticsSummary(
    total: UInt32 = 0,
    warnings: UInt32 = 0,
    errors: UInt32 = 0,
    critical: UInt32 = 0
) -> DiagnosticsSummary {
    DiagnosticsSummary(
        totalCount: total,
        warningCount: warnings,
        errorCount: errors,
        criticalCount: critical,
        latestCriticalMessage: nil,
        latestEventTimestamp: nil,
        appReadiness: "Ready",
        argyllVersion: "3.5.0",
        argyllPathCategory: "system_toolchain",
        retention: DiagnosticsRetentionStatus(
            retainedDays: 30,
            maxStorageMb: 50,
            maxPayloadBytes: 65536,
            eventCount: total,
            estimatedStorageBytes: 2048,
            lastPrunedAt: nil
        )
    )
}

func makeDiagnosticEvent(
    level: DiagnosticLevel = .info,
    category: DiagnosticCategory = .app,
    message: String = "Diagnostic event.",
    jobId: String? = nil,
    commandId: String? = nil
) -> DiagnosticEventRecord {
    DiagnosticEventRecord(
        id: UUID().uuidString,
        timestamp: "2026-04-26T18:30:00Z",
        level: level,
        category: category,
        source: "test.diagnostics",
        message: message,
        detailsJson: "{}",
        privacy: .public,
        jobId: jobId,
        commandId: commandId,
        profileId: nil,
        issueCaseId: nil,
        durationMs: nil,
        operationId: nil,
        parentOperationId: nil
    )
}
```

- [ ] **Step 6: Run Swift diagnostics model tests and commit**

Run:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx -derivedDataPath /tmp/ArgyllUXDerivedData test -only-testing:ArgyllUXTests/DiagnosticsModelTests
```

Expected: PASS.

Commit:

```bash
git add apple/ArgyllUX/Sources/Models/Shell/DiagnosticsModel.swift apple/ArgyllUX/Sources/Models/AppModel.swift apple/ArgyllUXTests/Support/AppModelTestSupport.swift apple/ArgyllUXTests/DiagnosticsModelTests.swift
git commit -m "feat: add Swift diagnostics model"
```

---

### Task 5: Diagnostics Window And Footer Replacement

**Files:**
- Create: `apple/ArgyllUX/Sources/Views/DiagnosticsWindowView.swift`
- Modify: `apple/ArgyllUX/Sources/App/ArgyllUXApp.swift`
- Modify: `apple/ArgyllUX/Sources/Views/AppShellView.swift`
- Modify: `apple/ArgyllUX/Sources/Views/FooterStatusBarView.swift`
- Delete: `apple/ArgyllUX/Sources/Views/LogViewerSheetView.swift`
- Test: `apple/ArgyllUXTests/AppModelShellTests.swift`

- [ ] **Step 1: Add shell test for diagnostics label and refresh path**

Add this test to `apple/ArgyllUXTests/AppModelShellTests.swift`:

```swift
@Test
func diagnosticsModelRefreshesThroughAppModel() async {
    let fakeEngine = FakeEngine()
    fakeEngine.diagnosticsSummaryValue = makeDiagnosticsSummary(total: 1)
    fakeEngine.diagnosticEventsValue = [
        makeDiagnosticEvent(level: .info, category: .environment, message: "Bootstrap environment captured.")
    ]

    let model = makeAppModel(fakeEngine: fakeEngine)
    await model.diagnostics.refresh()

    #expect(model.diagnostics.summary?.totalCount == 1)
    #expect(model.diagnostics.visibleEvents.first?.message == "Bootstrap environment captured.")
}
```

- [ ] **Step 2: Run shell test to verify current wiring gap**

Run:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx -derivedDataPath /tmp/ArgyllUXDerivedData test -only-testing:ArgyllUXTests/AppModelShellTests/diagnosticsModelRefreshesThroughAppModel
```

Expected: PASS after Task 4. If it fails, fix Task 4 wiring before changing views.

- [ ] **Step 3: Add the Diagnostics window**

Create `apple/ArgyllUX/Sources/Views/DiagnosticsWindowView.swift`:

```swift
import SwiftUI

struct DiagnosticsWindowView: View {
    static let windowID = "diagnostics"

    @ObservedObject var diagnostics: DiagnosticsModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filters
            Divider()

            HStack(spacing: 0) {
                eventList
                    .frame(minWidth: 420, idealWidth: 520, maxWidth: 640)

                Divider()

                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 980, minHeight: 620)
        .task {
            await diagnostics.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Diagnostics")
                    .font(.title2.weight(.semibold))
                Text("Privacy-safe app, workflow, toolchain, and command summary events.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if diagnostics.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button("Refresh") {
                Task { await diagnostics.refresh() }
            }
        }
        .padding(20)
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Picker("Level", selection: $diagnostics.levelFilter) {
                ForEach(DiagnosticsLevelFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)

            Picker("Category", selection: $diagnostics.categoryFilter) {
                ForEach(DiagnosticsCategoryFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)

            TextField("Search diagnostics", text: $diagnostics.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220)

            Toggle("Errors Only", isOn: $diagnostics.errorsOnly)

            Button("Apply") {
                Task { await diagnostics.refresh() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryStrip
            Divider()

            if diagnostics.visibleEvents.isEmpty {
                emptyState
            } else {
                List(diagnostics.visibleEvents, id: \.id, selection: Binding(
                    get: { diagnostics.selectedEventID },
                    set: { selectedID in
                        guard let selectedID,
                              let event = diagnostics.visibleEvents.first(where: { $0.id == selectedID })
                        else { return }
                        diagnostics.select(event)
                    }
                )) { event in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(levelTitle(event.level))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(levelColor(event.level))
                            Text(categoryTitle(event.category))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let duration = event.durationMs {
                                Text("\(duration) ms")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(event.message)
                            .font(.subheadline)
                            .lineLimit(2)

                        Text(event.timestamp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .tag(event.id)
                }
                .listStyle(.plain)
            }
        }
    }

    private var summaryStrip: some View {
        let summary = diagnostics.summary
        return HStack(spacing: 12) {
            summaryItem(title: "Events", value: "\(summary?.totalCount ?? 0)")
            summaryItem(title: "Warnings", value: "\(summary?.warningCount ?? 0)")
            summaryItem(title: "Errors", value: "\(summary?.errorCount ?? 0)")
            summaryItem(title: "Critical", value: "\(summary?.criticalCount ?? 0)")
        }
        .padding(14)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diagnostics are recording.")
                .font(.headline)
            Text("Privacy-safe events appear here after app, workflow, toolchain, or command activity. Full command output remains in CLI Transcript.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var detailPane: some View {
        Group {
            if let event = diagnostics.selectedEvent {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.message)
                                .font(.headline)
                            Text("\(levelTitle(event.level)) / \(categoryTitle(event.category)) / \(event.source)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if event.category == .cli, event.jobId != nil {
                            Button("Open CLI Transcript") {
                                diagnostics.openCliTranscript(for: event)
                            }
                        }
                    }

                    detailRows(for: event)

                    Text("Details")
                        .font(.subheadline.weight(.semibold))

                    ScrollView {
                        Text(prettyDetails(event.detailsJson))
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            } else {
                emptyState
            }
        }
    }

    private func detailRows(for event: DiagnosticEventRecord) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
            detailRow("Timestamp", event.timestamp)
            detailRow("Privacy", privacyTitle(event.privacy))
            detailRow("Job ID", event.jobId ?? "None")
            detailRow("Command ID", event.commandId ?? "None")
            detailRow("Profile ID", event.profileId ?? "None")
            detailRow("Operation ID", event.operationId ?? "None")
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.footnote)
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func levelTitle(_ level: DiagnosticLevel) -> String {
        switch level {
        case .debug: "Debug"
        case .info: "Info"
        case .warning: "Warning"
        case .error: "Error"
        case .critical: "Critical"
        }
    }

    private func categoryTitle(_ category: DiagnosticCategory) -> String {
        switch category {
        case .app: "App"
        case .ui: "UI"
        case .workflow: "Workflow"
        case .engine: "Engine"
        case .cli: "CLI"
        case .database: "Database"
        case .toolchain: "Toolchain"
        case .performance: "Performance"
        case .environment: "Environment"
        }
    }

    private func privacyTitle(_ privacy: DiagnosticPrivacy) -> String {
        switch privacy {
        case .public: "Public"
        case .internal: "Internal"
        case .sensitiveRedacted: "Sensitive Redacted"
        }
    }

    private func levelColor(_ level: DiagnosticLevel) -> Color {
        switch level {
        case .debug, .info: .secondary
        case .warning: .orange
        case .error, .critical: .red
        }
    }

    private func prettyDetails(_ details: String) -> String {
        guard let data = details.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8)
        else {
            return details
        }

        return text
    }
}
```

- [ ] **Step 4: Replace footer and shell wiring**

In `apple/ArgyllUX/Sources/Views/FooterStatusBarView.swift`, change:

```swift
    let onOpenErrorLogs: () -> Void
```

to:

```swift
    let onOpenDiagnostics: () -> Void
```

Change the footer button:

```swift
                Button("Error Log Viewer", action: onOpenErrorLogs)
```

to:

```swift
                Button("Diagnostics", action: onOpenDiagnostics)
```

In `apple/ArgyllUX/Sources/Views/AppShellView.swift`, remove:

```swift
    @State private var isShowingErrorLogViewer = false
```

Change the footer call site to:

```swift
                    onOpenDiagnostics: {
                        openWindow(id: DiagnosticsWindowView.windowID)
                        Task { await model.diagnostics.refresh() }
                    }
```

Remove the `.sheet(isPresented: $isShowingErrorLogViewer) { ... }` block.

In `apple/ArgyllUX/Sources/App/ArgyllUXApp.swift`, add a new scene after the CLI Transcript scene:

```swift
        Window("Diagnostics", id: DiagnosticsWindowView.windowID) {
            DiagnosticsWindowView(diagnostics: model.diagnostics)
        }
        .defaultSize(width: 1040, height: 680)
```

Delete `apple/ArgyllUX/Sources/Views/LogViewerSheetView.swift`.

- [ ] **Step 5: Run Swift tests and build**

Run:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx -derivedDataPath /tmp/ArgyllUXDerivedData test -only-testing:ArgyllUXTests/DiagnosticsModelTests -only-testing:ArgyllUXTests/AppModelShellTests/diagnosticsModelRefreshesThroughAppModel
```

Expected: PASS.

Run:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx -derivedDataPath /tmp/ArgyllUXDerivedData build
```

Expected: PASS.

Commit:

```bash
git add apple/ArgyllUX/Sources/Views/DiagnosticsWindowView.swift apple/ArgyllUX/Sources/App/ArgyllUXApp.swift apple/ArgyllUX/Sources/Views/AppShellView.swift apple/ArgyllUX/Sources/Views/FooterStatusBarView.swift apple/ArgyllUXTests/AppModelShellTests.swift
git rm apple/ArgyllUX/Sources/Views/LogViewerSheetView.swift
git commit -m "feat: replace error log viewer with diagnostics window"
```

---

### Task 6: Workflow, CLI Summary, And Performance Events

**Files:**
- Modify: `rust/engine/src/diagnostics.rs`
- Modify: `rust/engine/src/runner.rs`
- Modify: `rust/engine/src/lib.rs`
- Modify: `rust/engine/src/db.rs`
- Test: `rust/engine/src/runner.rs`
- Test: `rust/engine/src/db.rs`

- [ ] **Step 1: Add failing tests for sanitized command summaries**

In `rust/engine/src/diagnostics.rs`, add:

```rust
#[cfg(test)]
mod command_summary_tests {
    use super::*;

    #[test]
    fn command_details_use_executable_names_and_redacted_private_paths() {
        let details = command_summary_details(
            "colprof",
            &[
                "/opt/homebrew/bin/colprof".to_string(),
                "-v".to_string(),
                "-O".to_string(),
                "/Users/tylermiller/Profiles/P900 Rag v3.icc".to_string(),
            ],
            "succeeded",
            Some(0),
        );

        assert!(details.contains("\"command_kind\":\"colprof\""));
        assert!(details.contains("\"argv\":[\"colprof\",\"-v\",\"-O\",\"$HOME/.../P900 Rag v3.icc\"]"));
        assert!(!details.contains("/Users/tylermiller/Profiles"));
    }
}
```

In `rust/engine/src/runner.rs`, add a unit test beside the existing command arg tests:

```rust
#[test]
fn command_duration_ms_uses_saturating_milliseconds() {
    let started = std::time::Instant::now();
    std::thread::sleep(std::time::Duration::from_millis(2));
    assert!(duration_ms_since(started) >= 1);
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
cargo test -p argyllux_engine command_summary_tests runner::tests::command_duration_ms_uses_saturating_milliseconds -- --nocapture
```

Expected: FAIL because the helper functions do not exist.

- [ ] **Step 3: Add command summary helpers**

In `rust/engine/src/diagnostics.rs`, add:

```rust
pub(crate) fn command_summary_details(
    command_kind: &str,
    argv: &[String],
    status: &str,
    exit_code: Option<i32>,
) -> String {
    let sanitized_argv = argv
        .iter()
        .map(|arg| sanitize_command_arg(arg))
        .collect::<Vec<_>>();

    sanitize_event_input(DiagnosticEventInput {
        level: DiagnosticLevel::Info,
        category: DiagnosticCategory::Cli,
        source: "engine.cli".to_string(),
        message: "Command summary.".to_string(),
        details_json: json!({
            "command_kind": command_kind,
            "argv": sanitized_argv,
            "status": status,
            "exit_code": exit_code,
        })
        .to_string(),
        privacy: DiagnosticPrivacy::Internal,
        job_id: None,
        command_id: None,
        profile_id: None,
        issue_case_id: None,
        duration_ms: None,
        operation_id: None,
        parent_operation_id: None,
    })
    .details_json
}

fn sanitize_command_arg(arg: &str) -> String {
    if looks_like_private_path(arg) {
        redact_path(arg)
    } else if arg.starts_with("/opt/homebrew/") || arg.starts_with("/usr/local/") || arg.starts_with("/Applications/") {
        Path::new(arg)
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or(arg)
            .to_string()
    } else {
        arg.to_string()
    }
}
```

In `rust/engine/src/runner.rs`, add:

```rust
fn duration_ms_since(started_at: std::time::Instant) -> u32 {
    started_at.elapsed().as_millis().min(u32::MAX as u128) as u32
}
```

- [ ] **Step 4: Record CLI start/finish events**

In `rust/engine/src/runner.rs`, add `use crate::diagnostics;` and diagnostic model imports:

```rust
use crate::model::{DiagnosticCategory, DiagnosticEventInput, DiagnosticLevel, DiagnosticPrivacy};
```

Inside `run_command_with_transcript`, immediately after `let command_id = db::insert_job_command(...)`, add:

```rust
    let command_started_at = std::time::Instant::now();
    let _ = db::record_diagnostic_event(
        &config.database_path,
        &DiagnosticEventInput {
            level: DiagnosticLevel::Info,
            category: DiagnosticCategory::Cli,
            source: "engine.cli".to_string(),
            message: format!("Started {label}."),
            details_json: diagnostics::command_summary_details(label, &argv, "running", None),
            privacy: DiagnosticPrivacy::SensitiveRedacted,
            job_id: Some(context.job_id.clone()),
            command_id: Some(command_id.clone()),
            profile_id: None,
            issue_case_id: None,
            duration_ms: None,
            operation_id: Some(command_id.clone()),
            parent_operation_id: Some(context.job_id.clone()),
        },
    );
```

In the command spawn error branch, before `return Err(error.into());`, add:

```rust
            let _ = db::record_diagnostic_event(
                &config.database_path,
                &DiagnosticEventInput {
                    level: DiagnosticLevel::Error,
                    category: DiagnosticCategory::Cli,
                    source: "engine.cli".to_string(),
                    message: format!("Failed to start {label}."),
                    details_json: diagnostics::command_summary_details(label, &argv, "failed_to_start", None),
                    privacy: DiagnosticPrivacy::SensitiveRedacted,
                    job_id: Some(context.job_id.clone()),
                    command_id: Some(command_id.clone()),
                    profile_id: None,
                    issue_case_id: None,
                    duration_ms: Some(duration_ms_since(command_started_at)),
                    operation_id: Some(command_id.clone()),
                    parent_operation_id: Some(context.job_id.clone()),
                },
            );
```

After `db::finish_job_command(...)`, add:

```rust
    let _ = db::record_diagnostic_event(
        &config.database_path,
        &DiagnosticEventInput {
            level: if succeeded { DiagnosticLevel::Info } else { DiagnosticLevel::Error },
            category: DiagnosticCategory::Cli,
            source: "engine.cli".to_string(),
            message: format!(
                "{} {label}.",
                if succeeded { "Finished" } else { "Command failed" }
            ),
            details_json: diagnostics::command_summary_details(
                label,
                &argv,
                if succeeded { "succeeded" } else { "failed" },
                status.code(),
            ),
            privacy: DiagnosticPrivacy::SensitiveRedacted,
            job_id: Some(context.job_id.clone()),
            command_id: Some(command_id.clone()),
            profile_id: None,
            issue_case_id: None,
            duration_ms: Some(duration_ms_since(command_started_at)),
            operation_id: Some(command_id.clone()),
            parent_operation_id: Some(context.job_id.clone()),
        },
    );
```

- [ ] **Step 5: Record workflow state changes in bridge methods**

In `rust/engine/src/lib.rs`, add this helper:

```rust
fn record_workflow_event(
    config: &EngineConfig,
    job_id: &str,
    source: &str,
    message: &str,
    stage: Option<WorkflowStage>,
) {
    let details_json = serde_json::json!({
        "stage": stage.map(|item| format!("{item:?}")).unwrap_or_else(|| "unknown".to_string())
    })
    .to_string();

    let _ = db::record_diagnostic_event(
        &config.database_path,
        &DiagnosticEventInput {
            level: DiagnosticLevel::Info,
            category: DiagnosticCategory::Workflow,
            source: source.to_string(),
            message: message.to_string(),
            details_json,
            privacy: DiagnosticPrivacy::Public,
            job_id: Some(job_id.to_string()),
            command_id: None,
            profile_id: None,
            issue_case_id: None,
            duration_ms: None,
            operation_id: Some(job_id.to_string()),
            parent_operation_id: None,
        },
    );
}
```

In the success branch for `start_generate_target`, before `runner::spawn_job_task(...)`, add:

```rust
                record_workflow_event(
                    &config,
                    &job_id,
                    "engine.workflow.new_profile",
                    "New Profile target generation started.",
                    Some(detail.stage.clone()),
                );
```

Repeat the same pattern for:

- `mark_new_profile_printed`: message `New Profile chart marked printed.`
- `mark_new_profile_ready_to_measure`: message `New Profile marked ready to measure.`
- `start_measurement`: message `New Profile measurement started.`
- `start_build_profile`: message `New Profile profile build started.`
- `publish_new_profile`: message `New Profile published to Printer Profiles.`

- [ ] **Step 6: Run workflow and CLI tests**

Run:

```bash
cargo test -p argyllux_engine diagnostics::command_summary_tests runner::tests::command_duration_ms_uses_saturating_milliseconds -- --nocapture
```

Expected: PASS.

Run:

```bash
cargo test -p argyllux_engine
```

Expected: PASS.

Commit:

```bash
git add rust/engine/src/diagnostics.rs rust/engine/src/runner.rs rust/engine/src/lib.rs rust/engine/src/db.rs
git commit -m "feat: record workflow and CLI diagnostics"
```

---

### Task 7: Redacted Export Bundle

**Files:**
- Modify: `rust/engine/src/diagnostics.rs`
- Modify: `rust/engine/src/db.rs`
- Modify: `rust/engine/src/lib.rs`
- Modify: `apple/ArgyllUX/Sources/Models/EngineBridge.swift`
- Modify: `apple/ArgyllUX/Sources/Models/Shell/DiagnosticsModel.swift`
- Modify: `apple/ArgyllUX/Sources/Views/DiagnosticsWindowView.swift`
- Modify generated after command: `apple/ArgyllUX/Bridge/Generated/argyllux.swift`
- Test: `rust/engine/src/diagnostics.rs`
- Test: `rust/engine/src/db.rs`
- Test: `apple/ArgyllUXTests/DiagnosticsModelTests.swift`

- [ ] **Step 1: Write failing export tests**

In `rust/engine/src/db.rs`, add:

```rust
#[test]
fn export_bundle_writes_redacted_files_without_transcripts_by_default() {
    let temp = tempdir().unwrap();
    let config = build_config(temp.path());
    std::fs::create_dir_all(temp.path().join("app-support")).unwrap();
    initialize_database(&config).unwrap();

    record_diagnostic_event(
        &config.database_path,
        &DiagnosticEventInput {
            level: DiagnosticLevel::Error,
            category: DiagnosticCategory::Database,
            source: "engine.database".to_string(),
            message: "Database write failed.".to_string(),
            details_json: serde_json::json!({
                "path": "/Users/tylermiller/Library/Application Support/ArgyllUX/argyllux.sqlite"
            }).to_string(),
            privacy: DiagnosticPrivacy::Internal,
            job_id: None,
            command_id: None,
            profile_id: None,
            issue_case_id: None,
            duration_ms: None,
            operation_id: None,
            parent_operation_id: None,
        },
    )
    .unwrap();

    let output_dir = temp.path().join("export");
    let result = export_diagnostics_bundle(
        &config.database_path,
        &DiagnosticsExportOptions {
            output_directory: output_dir.to_string_lossy().to_string(),
            include_cli_transcripts: false,
            include_local_paths: false,
            job_ids: Vec::new(),
        },
    )
    .unwrap();

    assert!(result.success);
    let bundle = Path::new(&result.bundle_path);
    let diagnostics_jsonl = std::fs::read_to_string(bundle.join("diagnostics.jsonl")).unwrap();
    let readme = std::fs::read_to_string(bundle.join("README.md")).unwrap();

    assert!(diagnostics_jsonl.contains("$HOME/.../argyllux.sqlite"));
    assert!(!diagnostics_jsonl.contains("/Users/tylermiller"));
    assert!(readme.contains("Included CLI transcripts: 0"));
    assert!(!bundle.join("cli-transcripts").exists());
}
```

In `apple/ArgyllUXTests/DiagnosticsModelTests.swift`, add:

```swift
@Test
func exportReportsBridgeResultMessage() async {
    let fakeEngine = FakeEngine()
    fakeEngine.diagnosticsExportResult = DiagnosticsExportResult(
        success: true,
        bundlePath: "/tmp/ArgyllUX Diagnostics",
        message: "Diagnostics bundle exported.",
        includedEventCount: 2,
        includedTranscriptCount: 0,
        redactedPathsCount: 1
    )
    let model = DiagnosticsModel(bridge: EngineBridge(engine: fakeEngine))

    await model.exportBundle(to: "/tmp", includeCliTranscripts: false, includeLocalPaths: false)

    #expect(model.exportMessage == "Diagnostics bundle exported.")
    #expect(fakeEngine.lastDiagnosticsExportOptions?.includeCliTranscripts == false)
    #expect(fakeEngine.lastDiagnosticsExportOptions?.includeLocalPaths == false)
}
```

- [ ] **Step 2: Run export tests to verify failure**

Run:

```bash
cargo test -p argyllux_engine db::tests::export_bundle_writes_redacted_files_without_transcripts_by_default -- --nocapture
```

Expected: FAIL because `export_diagnostics_bundle` does not exist.

Run:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx -derivedDataPath /tmp/ArgyllUXDerivedData test -only-testing:ArgyllUXTests/DiagnosticsModelTests/exportReportsBridgeResultMessage
```

Expected: FAIL because Swift export methods do not exist.

- [ ] **Step 3: Add Rust export bundle function**

In `rust/engine/src/db.rs`, add:

```rust
pub fn export_diagnostics_bundle(
    database_path: &str,
    options: &DiagnosticsExportOptions,
) -> EngineResult<DiagnosticsExportResult> {
    let connection = open_connection(database_path)?;
    let bundle_name = format!("ArgyllUX Diagnostics {}", Utc::now().format("%Y-%m-%d %H-%M-%S"));
    let bundle_path = Path::new(&options.output_directory).join(bundle_name);
    ensure_directory(&bundle_path)?;

    let events = list_diagnostic_events(
        database_path,
        &DiagnosticEventFilter {
            levels: Vec::new(),
            categories: Vec::new(),
            search_text: None,
            job_id: None,
            profile_id: None,
            since_timestamp: None,
            until_timestamp: None,
            errors_only: false,
            limit: 500,
        },
    )?;

    let mut redacted_paths_count = 0u32;
    let diagnostics_body = events
        .iter()
        .map(|event| {
            let mut value = serde_json::to_value(event).unwrap_or_else(|_| serde_json::json!({}));
            if !options.include_local_paths {
                redacted_paths_count += redact_export_paths(&mut value);
            }
            serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
        })
        .collect::<Vec<_>>()
        .join("\n");
    std::fs::write(bundle_path.join("diagnostics.jsonl"), diagnostics_body)?;

    let environment = serde_json::json!({
        "database_schema_version": DATABASE_VERSION,
        "event_count": events.len(),
        "exported_at": iso_timestamp(),
        "local_paths_included": options.include_local_paths,
        "cli_transcripts_included": options.include_cli_transcripts
    });
    diagnostics::write_json_file(&bundle_path.join("environment.json"), &environment)?;

    let included_transcript_count = if options.include_cli_transcripts {
        export_selected_cli_transcripts(&connection, &bundle_path, &options.job_ids)?
    } else {
        0
    };

    std::fs::write(
        bundle_path.join("README.md"),
        diagnostics::export_readme(events.len() as u32, included_transcript_count, redacted_paths_count),
    )?;

    Ok(DiagnosticsExportResult {
        success: true,
        bundle_path: bundle_path.to_string_lossy().to_string(),
        message: "Diagnostics bundle exported.".to_string(),
        included_event_count: events.len() as u32,
        included_transcript_count,
        redacted_paths_count,
    })
}
```

Add these helpers:

```rust
fn redact_export_paths(value: &mut serde_json::Value) -> u32 {
    match value {
        serde_json::Value::Object(map) => map
            .values_mut()
            .map(redact_export_paths)
            .sum(),
        serde_json::Value::Array(items) => items.iter_mut().map(redact_export_paths).sum(),
        serde_json::Value::String(text) => {
            if text.contains("/Users/") || text.contains("/var/folders/") {
                *text = text
                    .replace("/Users/", "$HOME/")
                    .replace("/var/folders/", "$TEMP/");
                1
            } else {
                0
            }
        }
        _ => 0,
    }
}

fn export_selected_cli_transcripts(
    connection: &Connection,
    bundle_path: &Path,
    job_ids: &[String],
) -> EngineResult<u32> {
    if job_ids.is_empty() {
        return Ok(0);
    }

    let transcript_dir = bundle_path.join("cli-transcripts");
    ensure_directory(&transcript_dir)?;
    let mut written = 0u32;

    for job_id in job_ids {
        let commands = load_job_commands(connection, job_id)?;
        let body = commands
            .iter()
            .flat_map(|command| {
                std::iter::once(format!("$ {}", command.argv.join(" ")))
                    .chain(command.events.iter().map(|event| {
                        format!("[{:?}] {}", event.stream, event.message)
                    }))
            })
            .collect::<Vec<_>>()
            .join("\n");

        if !body.trim().is_empty() {
            std::fs::write(transcript_dir.join(format!("{job_id}.txt")), body)?;
            written += 1;
        }
    }

    Ok(written)
}
```

- [ ] **Step 4: Add bridge export method and regenerate**

In `rust/engine/src/lib.rs`, add:

```rust
    #[uniffi::method(name = "exportDiagnosticsBundle")]
    pub fn export_diagnostics_bundle(&self, options: DiagnosticsExportOptions) -> DiagnosticsExportResult {
        match with_config(&self.state, |config| {
            db::export_diagnostics_bundle(&config.database_path, &options)
        }) {
            Ok(result) => result,
            Err(error) => DiagnosticsExportResult {
                success: false,
                bundle_path: String::new(),
                message: format!("Diagnostics export failed: {error}"),
                included_event_count: 0,
                included_transcript_count: 0,
                redacted_paths_count: 0,
            },
        }
    }
```

Run:

```bash
scripts/build-swift-bridge.sh
```

Expected: PASS and generated bridge files update.

In `apple/ArgyllUX/Sources/Models/EngineBridge.swift`, add:

```swift
    func exportDiagnosticsBundle(options: DiagnosticsExportOptions) -> DiagnosticsExportResult {
        engine.exportDiagnosticsBundle(options: options)
    }
```

- [ ] **Step 5: Add Swift export model and UI action**

In `apple/ArgyllUX/Sources/Models/Shell/DiagnosticsModel.swift`, add:

```swift
    func exportBundle(to outputDirectory: String, includeCliTranscripts: Bool, includeLocalPaths: Bool) async {
        let result = await bridge.exportDiagnosticsBundle(options: DiagnosticsExportOptions(
            outputDirectory: outputDirectory,
            includeCliTranscripts: includeCliTranscripts,
            includeLocalPaths: includeLocalPaths,
            jobIds: visibleEvents.compactMap(\.jobId)
        ))
        exportMessage = result.message
    }
```

In `apple/ArgyllUX/Sources/Views/DiagnosticsWindowView.swift`, add export controls to the header after Refresh:

```swift
            Button("Export") {
                Task {
                    await diagnostics.exportBundle(
                        to: NSTemporaryDirectory(),
                        includeCliTranscripts: false,
                        includeLocalPaths: false
                    )
                }
            }
```

Add this alert to the outer view:

```swift
        .alert("Diagnostics Export", isPresented: Binding(
            get: { diagnostics.exportMessage != nil },
            set: { isPresented in
                if !isPresented {
                    diagnostics.clearExportMessage()
                }
            }
        )) {
            Button("OK", role: .cancel) {
                diagnostics.clearExportMessage()
            }
        } message: {
            Text(diagnostics.exportMessage ?? "")
        }
```

- [ ] **Step 6: Run export tests and commit**

Run:

```bash
cargo test -p argyllux_engine db::tests::export_bundle_writes_redacted_files_without_transcripts_by_default -- --nocapture
```

Expected: PASS.

Run:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx -derivedDataPath /tmp/ArgyllUXDerivedData test -only-testing:ArgyllUXTests/DiagnosticsModelTests/exportReportsBridgeResultMessage
```

Expected: PASS.

Commit:

```bash
git add rust/engine/src/diagnostics.rs rust/engine/src/db.rs rust/engine/src/lib.rs apple/ArgyllUX/Sources/Models/EngineBridge.swift apple/ArgyllUX/Sources/Models/Shell/DiagnosticsModel.swift apple/ArgyllUX/Sources/Views/DiagnosticsWindowView.swift apple/ArgyllUXTests/DiagnosticsModelTests.swift apple/ArgyllUXTests/Support/AppModelTestSupport.swift apple/ArgyllUX/Bridge/Generated/argyllux.swift apple/ArgyllUX/Bridge/Generated/argylluxFFI.h apple/ArgyllUX/Bridge/Generated/argylluxFFI.modulemap apple/ArgyllUX/Bridge/Generated/libargyllux_engine.a
git commit -m "feat: export redacted diagnostics bundles"
```

---

### Task 8: Enforcement Docs And Script

**Files:**
- Create: `docs/superpowers/templates/implementation-spec-template.md`
- Create: `docs/superpowers/code-review-checklist.md`
- Create: `scripts/check-diagnostics-section.sh`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Write the check script first**

Create `scripts/check-diagnostics-section.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

base_ref="${1:-HEAD}"
missing_files=()

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  [[ -f "$file" ]] || continue

  if grep -Eiq "(workflow|bridge|command|persistence|export|failure|public path|diagnostics|privacy|observability)" "$file"; then
    if ! grep -q "^## Diagnostics, Privacy, And Observability$" "$file"; then
      missing_files+=("$file")
    fi
  fi
done < <(git diff --name-only --diff-filter=ACMRT "$base_ref" -- \
  docs/superpowers/specs \
  docs/superpowers/plans \
  docs/plans)

if (( ${#missing_files[@]} > 0 )); then
  printf 'Missing "Diagnostics, Privacy, And Observability" section in relevant docs:\n' >&2
  printf ' - %s\n' "${missing_files[@]}" >&2
  exit 1
fi

printf 'Diagnostics section check passed.\n'
```

Run:

```bash
chmod +x scripts/check-diagnostics-section.sh
scripts/check-diagnostics-section.sh HEAD
```

Expected: PASS with `Diagnostics section check passed.` because no changed relevant docs are being compared against `HEAD` after the file is first created and untracked.

- [ ] **Step 2: Add template and review checklist**

Create `docs/superpowers/templates/implementation-spec-template.md`:

```markdown
# Feature Name Spec

## Purpose

State the product or engineering problem in one short paragraph.

## Scope

List the user-visible and system-visible behavior included in this work.

## Non-Goals

List behavior this work intentionally leaves out.

## Architecture

Describe ownership, source-of-truth boundaries, and public interfaces.

## Diagnostics, Privacy, And Observability

State which durable workflows, bridge calls, command execution paths, persistence paths, exports, user-visible failures, or public behavior changes need diagnostics.

State which private data must not be recorded. Include file contents, measurement contents, ICC/profile bytes, CGATS rows, user notes, arbitrary stdout/stderr, hostnames, usernames, serial numbers, device identifiers, network information, and full filesystem inventories when relevant.

State what will be emitted as privacy-safe events, what will remain only in job-scoped CLI Transcript, and what export redaction must prove.

## Testing

List unit tests, integration tests, build/typecheck commands, and manual smoke checks.
```

Create `docs/superpowers/code-review-checklist.md`:

```markdown
# Code Review Checklist

## Diagnostics, Privacy, And Observability

For changes touching durable workflows, bridge calls, command execution, persistence, export, user-visible failures, or public-path behavior changes:

- Confirm the implementation emits a structured diagnostic event or explicitly explains why one is not useful.
- Confirm same-class public paths are not left silently uninstrumented.
- Confirm private data is not recorded in global diagnostics: file contents, measurement contents, ICC/profile bytes, CGATS rows, user notes, arbitrary stdout/stderr, hostnames, usernames, serial numbers, device identifiers, network information, and full filesystem inventories.
- Confirm command output remains in CLI Transcript unless the user explicitly chooses to include it in an export.
- Confirm exported diagnostics are redacted by default and suitable for public issue reports.
```

- [ ] **Step 3: Update AGENTS and CLAUDE identically**

In both `AGENTS.md` and `CLAUDE.md`, add this section after `## Ownership Rules`:

```markdown
## Diagnostics, Privacy, And Observability

For durable workflows, bridge calls, command execution, persistence, export, user-visible failures, or public-path behavior changes, plans and implementation must explicitly address diagnostics.

- Emit structured diagnostics through the Rust-owned diagnostics store for normal operation, warnings, errors, performance timings, and sanitized environment context.
- Do not record private user data in global diagnostics: file contents, measurement contents, ICC/profile bytes, CGATS rows, user notes, arbitrary stdout/stderr, hostnames, usernames, serial numbers, device identifiers, network information, full filesystem inventories, or user-entered profile/printer/paper/Issue Case names.
- Keep full command output in the job-scoped CLI Transcript. Diagnostics may store command kind, sanitized argument shape, status, duration, exit code, and correlation IDs.
- Exported diagnostics must be redacted by default and suitable for a public GitHub issue unless the user explicitly includes CLI transcripts or local paths.
- When adding diagnostics to one public path, check neighboring same-class public paths and either instrument them or state what remains.
```

- [ ] **Step 4: Verify parity and run script**

Run:

```bash
cmp -s AGENTS.md CLAUDE.md
```

Expected: PASS with no output.

Run:

```bash
scripts/check-diagnostics-section.sh HEAD
```

Expected: PASS because this plan and the spec include the diagnostics section.

Commit:

```bash
git add docs/superpowers/templates/implementation-spec-template.md docs/superpowers/code-review-checklist.md scripts/check-diagnostics-section.sh AGENTS.md CLAUDE.md
git commit -m "docs: require diagnostics planning coverage"
```

---

### Task 9: Full Validation And Manual Smoke Test

**Files:**
- No new source files.
- Verify the full changed set.

- [ ] **Step 1: Run Rust tests**

Run:

```bash
cargo test -p argyllux_engine
```

Expected: PASS.

- [ ] **Step 2: Regenerate bridge after final Rust changes**

Run:

```bash
scripts/build-swift-bridge.sh
```

Expected: PASS. If generated files change, review the diff and include them in the final validation commit.

- [ ] **Step 3: Run Xcode build**

Run:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx -derivedDataPath /tmp/ArgyllUXDerivedData build
```

Expected: PASS.

- [ ] **Step 4: Run Xcode tests**

Run:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project apple/ArgyllUX.xcodeproj -scheme ArgyllUX -sdk macosx -derivedDataPath /tmp/ArgyllUXDerivedData test
```

Expected: PASS. If `testmanagerd` fails without compile or assertion failures, classify it as environment-only and rerun once before finalizing.

- [ ] **Step 5: Run documentation enforcement**

Run:

```bash
scripts/check-diagnostics-section.sh HEAD
cmp -s AGENTS.md CLAUDE.md
```

Expected: both commands PASS.

- [ ] **Step 6: Manual smoke test**

Run the app from Xcode or with the existing local run workflow, then verify:

```text
1. Bootstrap the app.
2. Open Diagnostics from the footer.
3. Confirm the summary strip shows event totals and environment/toolchain context.
4. Start or resume New Profile.
5. Run or simulate Generate Target.
6. Confirm Diagnostics shows workflow and CLI summary events.
7. Open the related CLI Transcript from a command-linked Diagnostics event.
8. Confirm full stdout/stderr appears only in CLI Transcript.
9. Trigger a failure path such as an invalid toolchain path or failed delete.
10. Confirm an error event appears in Diagnostics.
11. Export a default diagnostics bundle.
12. Inspect diagnostics.jsonl, environment.json, and README.md.
13. Confirm no full /Users path, user-entered profile/printer/paper name, stdout/stderr payload, or file contents appear in the default export.
```

- [ ] **Step 7: Final commit if validation generated changes**

If the bridge or docs script permissions changed during validation, commit them:

```bash
git add apple/ArgyllUX/Bridge/Generated scripts/check-diagnostics-section.sh
git commit -m "chore: refresh diagnostics generated bridge"
```

Expected: commit only if there are actual validation-generated changes.

---

## Self-Review

Spec coverage:

- Normal operation events: Tasks 3, 4, and 6.
- Always-on production diagnostics with bounded retention: Task 2 and bootstrap pruning in Task 3.
- Privacy-safe global stream: Task 1 sanitizer, Task 2 persistence path, Task 7 export redaction.
- Redacted issue-report bundle: Task 7.
- CLI Transcript preservation: Tasks 5 and 6 keep full stdout/stderr in transcript only.
- Diagnostic event model fields: Tasks 1 and 2.
- Footer action renamed to Diagnostics: Task 5.
- Summary/filter/list/detail UI: Task 5.
- CLI links from diagnostics to transcript: Tasks 4 and 5.
- Environment snapshot: Task 3 and Task 7.
- Enforcement docs and check script: Task 8.
- Rust, Swift, boundary, and manual validation: Task 9.

Placeholder scan:

- The plan uses concrete paths, commands, expected outcomes, and code snippets for the new or changed interfaces.
- Each task can be executed without inventing missing names, files, or test intent.

Type consistency:

- Rust bridge names are `recordDiagnosticEvent`, `listDiagnosticEvents`, `getDiagnosticsSummary`, and `exportDiagnosticsBundle`.
- Swift wrapper names match those bridge names.
- `details_json` in Rust maps to `detailsJson` in Swift generated records.
- `DiagnosticPrivacy::SensitiveRedacted` maps to Swift `.sensitiveRedacted`.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-26-diagnostics-system.md`. Two execution options:

**1. Subagent-Driven (recommended)** - Dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints.
