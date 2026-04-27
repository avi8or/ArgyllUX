//! Rust-owned diagnostic event sanitization and privacy-safe diagnostic helpers.
#![allow(dead_code)]

use crate::model::{
    DiagnosticCategory, DiagnosticEventInput, DiagnosticEventRecord, DiagnosticLevel,
    DiagnosticPrivacy, DiagnosticsRetentionStatus, ToolchainStatus,
};
use crate::support::{EngineResult, iso_timestamp};
use serde_json::{Map, Value, json};
use std::path::Path;

pub(crate) const DEFAULT_RETENTION_DAYS: u32 = 30;
pub(crate) const DEFAULT_MAX_STORAGE_MB: u32 = 50;
pub(crate) const MAX_DIAGNOSTIC_DETAILS_BYTES: usize = 64 * 1024;

const PRIVATE_KEY_CONCEPTS: &[&[&str]] = &[
    &["profile", "name"],
    &["printer", "name"],
    &["paper", "name"],
    &["issue", "case", "title"],
    &["stdout"],
    &["stderr"],
    &["hostname"],
    &["host", "name"],
    &["username"],
    &["user", "name"],
    &["serial", "number"],
    &["device", "identifier"],
    &["network"],
    &["notes"],
];

#[derive(Debug, Clone, PartialEq, Eq)]
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

/// Sanitizes a diagnostic event before any persistence boundary can store it.
pub(crate) fn sanitize_event_input(input: DiagnosticEventInput) -> SanitizedDiagnosticEventInput {
    let mut changed = false;
    let raw_details = input.details_json.trim();
    let mut details = if raw_details.is_empty() {
        if input.details_json != raw_details {
            changed = true;
        }
        Value::Object(Map::new())
    } else {
        match serde_json::from_str::<Value>(raw_details) {
            Ok(value) => value,
            Err(_) => {
                changed = true;
                json!({ "unstructured": "[redacted]" })
            }
        }
    };

    changed |= sanitize_json_value(&mut details);

    let (details_json, truncated) =
        truncate_details_json(serde_json::to_string(&details).unwrap_or_else(|_| "{}".to_string()));
    changed |= truncated;

    let (source, source_changed) =
        sanitize_free_text_field(input.source, "engine", "engine.redacted");
    let (message, message_changed) = sanitize_free_text_field(
        input.message,
        "Diagnostic event.",
        "[redacted diagnostic message]",
    );
    changed |= source_changed || message_changed;

    SanitizedDiagnosticEventInput {
        level: input.level,
        category: input.category,
        source,
        message,
        details_json,
        privacy: if changed {
            DiagnosticPrivacy::SensitiveRedacted
        } else {
            input.privacy
        },
        job_id: trim_option(input.job_id),
        command_id: trim_option(input.command_id),
        profile_id: trim_option(input.profile_id),
        issue_case_id: trim_option(input.issue_case_id),
        duration_ms: input.duration_ms,
        operation_id: trim_option(input.operation_id),
        parent_operation_id: trim_option(input.parent_operation_id),
    }
}

/// Builds the persisted diagnostic record from already-sanitized event input.
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

/// Returns non-identifying environment facts for bootstrap diagnostics.
pub(crate) fn bootstrap_environment_details(
    app_support_path: &str,
    database_path: &str,
    toolchain_status: &ToolchainStatus,
    database_schema_version: u32,
) -> String {
    json!({
        "cpu_architecture": std::env::consts::ARCH,
        "operating_system": std::env::consts::OS,
        "app_support_path_category": path_category(Some(app_support_path)),
        "database_path_category": path_category(Some(database_path)),
        "argyll_path_category": path_category(toolchain_status.resolved_install_path.as_deref()),
        "argyll_version": toolchain_status.argyll_version.clone().unwrap_or_else(|| "not_resolved".to_string()),
        "database_schema_version": database_schema_version,
    })
    .to_string()
}

/// Builds a privacy-safe CLI diagnostic detail payload without command output.
pub(crate) fn command_summary_details(
    command_kind: &str,
    argv: &[String],
    status: &str,
    exit_code: Option<i32>,
) -> String {
    let summarized_argv = summarize_command_argv(argv);

    sanitize_event_input(DiagnosticEventInput {
        level: DiagnosticLevel::Info,
        category: DiagnosticCategory::Cli,
        source: "engine.cli".to_string(),
        message: "Command summary.".to_string(),
        details_json: json!({
            "command_kind": command_kind,
            "argv": summarized_argv,
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

/// Produces the configured diagnostics retention status with runtime counters.
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
        "applications"
    } else if path.starts_with("/opt/homebrew/") || path.starts_with("/usr/local/") {
        "system_toolchain"
    } else if path.starts_with("/Users/") {
        "user_home"
    } else if path.starts_with("/tmp/") || path.starts_with("/var/folders/") {
        "temporary"
    } else {
        "other"
    }
    .to_string()
}

pub(crate) fn export_readme(
    included_events: u32,
    included_transcripts: u32,
    redacted_paths: u32,
) -> String {
    format!(
        "# ArgyllUX Diagnostics Bundle\n\nThis bundle contains privacy-redacted diagnostics generated by ArgyllUX.\n\nIncluded diagnostic events: {included_events}\nIncluded CLI transcripts: {included_transcripts}\nRedacted paths: {redacted_paths}\n\nDiagnostics redact private names, local paths, device identifiers, and command output summaries before export. CLI transcripts are included only when explicitly requested.\n"
    )
}

pub(crate) fn write_json_file(path: &Path, value: &Value) -> EngineResult<()> {
    std::fs::write(path, serde_json::to_string_pretty(value)?)?;
    Ok(())
}

/// Redacts path-like substrings at export time so older malformed rows cannot
/// leak local filesystem details even if they predate the diagnostics sanitizer.
pub(crate) fn redact_export_text(value: &str) -> (String, u32) {
    const PREFIXES: [&str; 3] = ["/Users/", "/var/folders/", "/private/var/"];

    let mut output = String::with_capacity(value.len());
    let mut remaining = value;
    let mut redacted_count = 0;

    while let Some((start, _prefix)) = PREFIXES
        .iter()
        .filter_map(|prefix| remaining.find(prefix).map(|index| (index, *prefix)))
        .min_by_key(|(index, _)| *index)
    {
        output.push_str(&remaining[..start]);
        let path_candidate = &remaining[start..];
        let end = path_candidate
            .char_indices()
            .skip(1)
            .find_map(|(index, character)| {
                matches!(character, '"' | '\'' | '<' | '>' | '\n' | '\r' | '\t').then_some(index)
            })
            .unwrap_or(path_candidate.len());
        let raw_path = &path_candidate[..end];

        output.push_str(&redact_path(raw_path));
        redacted_count += 1;
        remaining = &path_candidate[end..];
    }

    output.push_str(remaining);
    (output, redacted_count)
}

pub(crate) fn diagnostic_id() -> String {
    format!(
        "diag-{}",
        chrono::Utc::now().timestamp_nanos_opt().unwrap_or_default()
    )
}

pub(crate) fn now_timestamp() -> String {
    iso_timestamp()
}

fn sanitize_json_value(value: &mut Value) -> bool {
    match value {
        Value::Object(object) => sanitize_object(object),
        Value::Array(values) => {
            let mut changed = false;
            for value in values {
                if sanitize_json_value(value) {
                    changed = true;
                }
            }
            changed
        }
        Value::String(text) => sanitize_detail_string(text),
        _ => false,
    }
}

fn sanitize_object(object: &mut Map<String, Value>) -> bool {
    let mut changed = false;

    for (key, value) in object.iter_mut() {
        let key = key.as_str();
        if is_private_value_key(key) {
            if value != "[redacted]" {
                *value = Value::String("[redacted]".to_string());
                changed = true;
            }
        } else if key == "argv" {
            changed |= sanitize_argv(value);
        } else if is_path_key(key) {
            match value {
                Value::String(path) => {
                    let redacted = redact_path(path);
                    if *path != redacted {
                        *path = redacted;
                        changed = true;
                    }
                }
                _ => changed |= sanitize_json_value(value),
            }
        } else {
            changed |= sanitize_json_value(value);
        }
    }

    changed
}

fn sanitize_argv(value: &mut Value) -> bool {
    let Value::Array(arguments) = value else {
        return sanitize_json_value(value);
    };

    let mut changed = false;
    for argument in arguments {
        match argument {
            Value::String(text) if looks_like_private_path(text) => {
                let redacted = redact_path(text);
                if *text != redacted {
                    *text = redacted;
                    changed = true;
                }
            }
            Value::String(text) if text.starts_with('/') => {
                let filename = Path::new(text)
                    .file_name()
                    .and_then(|name| name.to_str())
                    .unwrap_or(text)
                    .to_string();
                if *text != filename {
                    *text = filename;
                    changed = true;
                }
            }
            _ => changed |= sanitize_json_value(argument),
        }
    }

    changed
}

fn looks_like_private_path(value: &str) -> bool {
    value.contains("/Users/") || value.contains("/var/folders/") || value.contains("/private/var/")
}

fn summarize_command_argv(argv: &[String]) -> Vec<String> {
    let Some((executable, arguments)) = argv.split_first() else {
        return Vec::new();
    };

    let mut summary = vec![command_executable_name(executable)];
    let mut index = 0;
    while index < arguments.len() {
        let argument = &arguments[index];
        if is_sensitive_value_flag(argument) {
            summary.push(argument.to_string());
            if index + 1 < arguments.len() {
                summary.push("[redacted value]".to_string());
                index += 2;
            } else {
                index += 1;
            }
        } else if is_safe_value_flag(argument)
            && arguments
                .get(index + 1)
                .is_some_and(|value| is_safe_operational_value(value))
        {
            summary.push(argument.to_string());
            summary.push(arguments[index + 1].to_string());
            index += 2;
        } else if argument.starts_with('-') {
            summary.push(argument.to_string());
            index += 1;
        } else {
            summary.push("[redacted value]".to_string());
            index += 1;
        }
    }

    summary
}

fn command_executable_name(arg: &str) -> String {
    if arg.starts_with('/') {
        Path::new(arg)
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("[redacted executable]")
            .to_string()
    } else {
        arg.to_string()
    }
}

fn is_sensitive_value_flag(argument: &str) -> bool {
    matches!(argument, "-D" | "-A" | "-M" | "-O" | "-c" | "-k")
}

fn is_safe_value_flag(argument: &str) -> bool {
    matches!(argument, "-f" | "-l" | "-L" | "-T" | "-p" | "-Q" | "-v")
}

fn is_safe_operational_value(value: &str) -> bool {
    !looks_like_private_path(value)
        && !value.starts_with('-')
        && !value.contains('/')
        && value
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || matches!(character, '_' | '.'))
}

fn sanitize_detail_string(value: &mut String) -> bool {
    if looks_like_private_path(value) {
        let redacted = redact_path(value);
        if *value != redacted {
            *value = redacted;
            return true;
        }
    } else if free_text_may_contain_private_payload(value) {
        *value = "[redacted]".to_string();
        return true;
    }

    false
}

fn is_private_value_key(key: &str) -> bool {
    let tokens = key_tokens(key);
    PRIVATE_KEY_CONCEPTS
        .iter()
        .any(|concept| contains_token_sequence(&tokens, concept))
}

fn is_path_key(key: &str) -> bool {
    let tokens = key_tokens(key);
    tokens.iter().any(|token| token == "path")
}

fn key_tokens(key: &str) -> Vec<String> {
    let mut tokens = Vec::new();
    let mut current = String::new();
    let mut previous_was_lowercase = false;

    for character in key.chars() {
        if character.is_ascii_alphanumeric() {
            if character.is_ascii_uppercase() && previous_was_lowercase && !current.is_empty() {
                tokens.push(std::mem::take(&mut current));
            }
            current.push(character.to_ascii_lowercase());
            previous_was_lowercase = character.is_ascii_lowercase() || character.is_ascii_digit();
        } else {
            if !current.is_empty() {
                tokens.push(std::mem::take(&mut current));
            }
            previous_was_lowercase = false;
        }
    }

    if !current.is_empty() {
        tokens.push(current);
    }

    tokens
}

fn contains_token_sequence(tokens: &[String], sequence: &[&str]) -> bool {
    !sequence.is_empty()
        && tokens.windows(sequence.len()).any(|window| {
            window
                .iter()
                .map(String::as_str)
                .eq(sequence.iter().copied())
        })
}

fn sanitize_free_text_field(
    value: String,
    fallback: &str,
    unsafe_fallback: &str,
) -> (String, bool) {
    let trimmed = trim_or_fallback(value, fallback);
    if free_text_may_contain_private_payload(&trimmed) {
        // Persisted diagnostic source/message fields must stay summary-only.
        // If free text resembles a path-bearing payload or stdout/stderr excerpt,
        // keep the correlation event and replace the ambiguous text wholesale.
        (unsafe_fallback.to_string(), true)
    } else {
        (trimmed, false)
    }
}

fn free_text_may_contain_private_payload(value: &str) -> bool {
    let lower = value.to_ascii_lowercase();
    looks_like_private_path(value)
        || lower.contains("stdout:")
        || lower.contains("stdout=")
        || lower.contains("stderr:")
        || lower.contains("stderr=")
        || lower.contains("standard output:")
        || lower.contains("standard error:")
}

fn redact_path(path: &str) -> String {
    if path.starts_with("/Users/") {
        redacted_home_path(path)
    } else if path.starts_with("/var/folders/") || path.starts_with("/private/var/") {
        redacted_path("$TEMP", path)
    } else if path.starts_with("/Applications/") {
        redacted_path("/Applications", path)
    } else if path.starts_with("/opt/homebrew/") || path.starts_with("/usr/local/") {
        Path::new(path)
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("[redacted path]")
            .to_string()
    } else if path.starts_with('/') {
        "[redacted path]".to_string()
    } else if looks_like_private_path(path) {
        "[redacted path]".to_string()
    } else {
        path.to_string()
    }
}

fn redacted_path(prefix: &str, path: &str) -> String {
    let Some(filename) = path
        .trim_end_matches('/')
        .rsplit('/')
        .find(|component| !component.is_empty())
    else {
        return prefix.to_string();
    };

    format!("{prefix}/.../{filename}")
}

fn redacted_home_path(path: &str) -> String {
    let components: Vec<&str> = path
        .trim_end_matches('/')
        .split('/')
        .filter(|component| !component.is_empty())
        .collect();

    if components.len() <= 2 {
        "$HOME".to_string()
    } else {
        format!("$HOME/.../{}", components[components.len() - 1])
    }
}

fn truncate_details_json(details_json: String) -> (String, bool) {
    if details_json.len() <= MAX_DIAGNOSTIC_DETAILS_BYTES {
        return (details_json, false);
    }

    (
        json!({
            "truncated": true,
            "original_bytes": details_json.len(),
            "max_bytes": MAX_DIAGNOSTIC_DETAILS_BYTES,
        })
        .to_string(),
        true,
    )
}

fn trim_or_fallback(value: String, fallback: &str) -> String {
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
                "-D".to_string(),
                "P900 Rag v3".to_string(),
                "-A".to_string(),
                "Studio P900".to_string(),
                "-M".to_string(),
                "SureColor P900".to_string(),
                "-O".to_string(),
                "/Users/tylermiller/Profiles/P900 Rag v3.icc".to_string(),
                "/Users/tylermiller/Work/P900 Rag v3".to_string(),
            ],
            "succeeded",
            Some(0),
        );

        assert!(details.contains("\"command_kind\":\"colprof\""));
        assert!(
            details.contains(
                "\"argv\":[\"colprof\",\"-v\",\"-D\",\"[redacted value]\",\"-A\",\"[redacted value]\",\"-M\",\"[redacted value]\",\"-O\",\"[redacted value]\",\"[redacted value]\"]"
            )
        );
        assert!(!details.contains("P900 Rag v3"));
        assert!(!details.contains("Studio P900"));
        assert!(!details.contains("SureColor P900"));
        assert!(!details.contains("/Users/tylermiller/Profiles"));
        assert!(!details.contains("/Users/tylermiller/Work"));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{
        DiagnosticCategory, DiagnosticEventInput, DiagnosticLevel, DiagnosticPrivacy,
    };

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
            }"#,
        ));

        assert_eq!(sanitized.message, "Command finished.");
        assert!(
            sanitized
                .details_json
                .contains("\"profile_name\":\"[redacted]\"")
        );
        assert!(
            sanitized
                .details_json
                .contains("\"path\":\"$HOME/.../P900 Rag v3.icc\"")
        );
        assert!(sanitized.details_json.contains("\"stdout\":\"[redacted]\""));
        assert!(
            sanitized
                .details_json
                .contains("\"argv\":[\"targen\",\"-v\",\"$HOME/.../p900\"]")
        );
        assert_eq!(sanitized.privacy, DiagnosticPrivacy::SensitiveRedacted);
    }

    #[test]
    fn sanitizer_redacts_private_source_and_message_before_persistence() {
        let mut input = input_with_details(r#"{"safe":"kept"}"#);
        input.source = "engine.cli /Users/tylermiller/private/run".to_string();
        input.message =
            "stderr: secret command output from /Users/tylermiller/job/p900".to_string();

        let sanitized = sanitize_event_input(input);

        assert_eq!(sanitized.source, "engine.redacted");
        assert_eq!(sanitized.message, "[redacted diagnostic message]");
        assert!(sanitized.details_json.contains("\"safe\":\"kept\""));
        assert!(!sanitized.source.contains("/Users/tylermiller"));
        assert!(!sanitized.message.contains("/Users/tylermiller"));
        assert!(!sanitized.message.contains("secret command output"));
        assert_eq!(sanitized.privacy, DiagnosticPrivacy::SensitiveRedacted);
    }

    #[test]
    fn sanitizer_redacts_malformed_non_empty_details_before_persistence() {
        let sanitized = sanitize_event_input(input_with_details(
            "stderr: secret command output from /Users/tylermiller/job/p900",
        ));

        assert_eq!(sanitized.details_json, r#"{"unstructured":"[redacted]"}"#);
        assert!(!sanitized.details_json.contains("/Users/tylermiller"));
        assert!(!sanitized.details_json.contains("secret command output"));
        assert!(!sanitized.details_json.contains("stderr:"));
        assert_eq!(sanitized.privacy, DiagnosticPrivacy::SensitiveRedacted);
    }

    #[test]
    fn sanitizer_redacts_unsafe_detail_string_under_neutral_key() {
        let sanitized = sanitize_event_input(input_with_details(
            r#"{"detail":"stderr: secret command output"}"#,
        ));

        assert!(sanitized.details_json.contains("\"detail\":\"[redacted]\""));
        assert!(!sanitized.details_json.contains("secret command output"));
        assert_eq!(sanitized.privacy, DiagnosticPrivacy::SensitiveRedacted);
    }

    #[test]
    fn sanitizer_redacts_unsafe_top_level_detail_string() {
        let sanitized = sanitize_event_input(input_with_details(
            &serde_json::json!("stdout: secret command output").to_string(),
        ));

        assert_eq!(sanitized.details_json, "\"[redacted]\"");
        assert!(!sanitized.details_json.contains("secret command output"));
        assert_eq!(sanitized.privacy, DiagnosticPrivacy::SensitiveRedacted);
    }

    #[test]
    fn sanitizer_preserves_safe_detail_string_values() {
        let sanitized =
            sanitize_event_input(input_with_details(r#"{"detail":"Command finished."}"#));

        assert!(
            sanitized
                .details_json
                .contains("\"detail\":\"Command finished.\"")
        );
        assert_eq!(sanitized.privacy, DiagnosticPrivacy::Internal);
    }

    #[test]
    fn export_readme_reports_included_transcripts_with_task_phrase() {
        let readme = export_readme(2, 0, 1);

        assert!(readme.contains("Included diagnostic events: 2"));
        assert!(readme.contains("Included CLI transcripts: 0"));
        assert!(readme.contains("Redacted paths: 1"));
    }

    #[test]
    fn export_redaction_replaces_legacy_local_path_text() {
        let (redacted, count) = redact_export_text(
            r#"{"path":"/Users/tylermiller/Library/Application Support/ArgyllUX/argyllux.sqlite","tmp":"/private/var/folders/run"}"#,
        );

        assert_eq!(count, 2);
        assert!(redacted.contains("$HOME"));
        assert!(redacted.contains("$TEMP"));
        assert!(!redacted.contains("/Users/tylermiller"));
        assert!(!redacted.contains("/private/var/"));
    }

    #[test]
    fn sanitizer_redacts_normalized_private_key_concepts() {
        let sanitized = sanitize_event_input(input_with_details(
            r#"{
                "profileName":"P900 Rag v3",
                "serialNumber":"abc-123",
                "planning_profile_name":"Planning profile",
                "measurement_notes":"private notes",
                "paper-name":"Rag Paper",
                "safe_label":"public summary"
            }"#,
        ));

        assert!(
            sanitized
                .details_json
                .contains("\"profileName\":\"[redacted]\"")
        );
        assert!(
            sanitized
                .details_json
                .contains("\"serialNumber\":\"[redacted]\"")
        );
        assert!(
            sanitized
                .details_json
                .contains("\"planning_profile_name\":\"[redacted]\"")
        );
        assert!(
            sanitized
                .details_json
                .contains("\"measurement_notes\":\"[redacted]\"")
        );
        assert!(
            sanitized
                .details_json
                .contains("\"paper-name\":\"[redacted]\"")
        );
        assert!(
            sanitized
                .details_json
                .contains("\"safe_label\":\"public summary\"")
        );
        assert!(!sanitized.details_json.contains("P900 Rag v3"));
        assert!(!sanitized.details_json.contains("abc-123"));
        assert!(!sanitized.details_json.contains("private notes"));
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
    fn sanitizer_visits_every_array_entry_before_persistence() {
        let sanitized = sanitize_event_input(input_with_details(
            r#"{
                "events":[
                    "/Users/tylermiller/Profiles/First.icc",
                    {"stdout":"second secret"},
                    {"path":"/Users/tylermiller/Profiles/Third.icc"}
                ]
            }"#,
        ));

        assert!(sanitized.details_json.contains("\"$HOME/.../First.icc\""));
        assert!(sanitized.details_json.contains("\"stdout\":\"[redacted]\""));
        assert!(
            sanitized
                .details_json
                .contains("\"path\":\"$HOME/.../Third.icc\"")
        );
        assert!(!sanitized.details_json.contains("/Users/tylermiller"));
        assert!(!sanitized.details_json.contains("second secret"));
        assert_eq!(sanitized.privacy, DiagnosticPrivacy::SensitiveRedacted);
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
