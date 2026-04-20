use crate::model::{EngineConfig, ToolchainState, ToolchainStatus};
use crate::support::{iso_timestamp, normalized_directory_candidates};
use std::collections::HashSet;
use std::env;
use std::path::{Path, PathBuf};
use std::process::Command;

const REQUIRED_EXECUTABLES: &[&str] = &[
    "targen",
    "printtarg",
    "chartread",
    "colprof",
    "spotread",
    "scanin",
    "printcal",
    "colverify",
];

const COMMON_INSTALL_ROOTS: &[&str] = &[
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/Applications/ArgyllCMS/bin",
    "/Applications/Argyll_V3.3.0/bin",
    "/Applications/Argyll_V3.2.0/bin",
    "/Applications/Argyll_V3.1.0/bin",
];

#[derive(Debug, Clone)]
struct CandidateResult {
    path: PathBuf,
    discovered: Vec<String>,
    missing: Vec<String>,
    argyll_version: Option<String>,
}

pub fn required_executables() -> &'static [&'static str] {
    REQUIRED_EXECUTABLES
}

pub fn discover_toolchain(config: &EngineConfig) -> ToolchainStatus {
    discover_toolchain_internal(config, env::var_os("PATH"), COMMON_INSTALL_ROOTS)
}

fn discover_toolchain_internal(
    config: &EngineConfig,
    env_path: Option<std::ffi::OsString>,
    common_roots: &[&str],
) -> ToolchainStatus {
    let mut seen = HashSet::new();
    let mut candidates = Vec::new();

    if let Some(path) = config.argyll_override_path.as_deref() {
        collect_candidate_roots(Path::new(path), &mut seen, &mut candidates);
    }

    for root in &config.additional_search_roots {
        collect_candidate_roots(Path::new(root), &mut seen, &mut candidates);
    }

    for root in common_roots {
        collect_candidate_roots(Path::new(root), &mut seen, &mut candidates);
    }

    if let Some(env_path) = env_path.as_deref() {
        for path in env::split_paths(env_path) {
            collect_candidate_roots(&path, &mut seen, &mut candidates);
        }
    }

    let mut best_partial: Option<CandidateResult> = None;

    for candidate in candidates {
        let inspected = inspect_candidate(&candidate);
        if inspected.missing.is_empty() {
            return status_from_candidate(ToolchainState::Ready, inspected);
        }

        if !inspected.discovered.is_empty() {
            let best_partial_count = best_partial
                .as_ref()
                .map(|result| result.discovered.len())
                .unwrap_or(0);

            if inspected.discovered.len() > best_partial_count {
                best_partial = Some(inspected);
            }
        }
    }

    if let Some(candidate) = best_partial {
        status_from_candidate(ToolchainState::Partial, candidate)
    } else {
        ToolchainStatus {
            state: ToolchainState::NotFound,
            resolved_install_path: None,
            discovered_executables: Vec::new(),
            missing_executables: REQUIRED_EXECUTABLES
                .iter()
                .map(|item| (*item).to_string())
                .collect(),
            argyll_version: None,
            last_validation_time: Some(iso_timestamp()),
        }
    }
}

fn collect_candidate_roots(path: &Path, seen: &mut HashSet<String>, candidates: &mut Vec<PathBuf>) {
    for candidate in normalized_directory_candidates(path) {
        let key = candidate.to_string_lossy().to_string();
        if seen.insert(key) {
            candidates.push(candidate);
        }
    }
}

fn inspect_candidate(path: &Path) -> CandidateResult {
    let mut discovered = Vec::new();
    let mut missing = Vec::new();

    for executable in REQUIRED_EXECUTABLES {
        let executable_path = path.join(executable);
        if executable_path.is_file() {
            discovered.push((*executable).to_string());
        } else {
            missing.push((*executable).to_string());
        }
    }

    let argyll_version = preferred_version_probe(&discovered)
        .and_then(|executable| probe_argyll_version(&path.join(executable)));

    CandidateResult {
        path: path.to_path_buf(),
        discovered,
        missing,
        argyll_version,
    }
}

fn status_from_candidate(state: ToolchainState, candidate: CandidateResult) -> ToolchainStatus {
    ToolchainStatus {
        state,
        resolved_install_path: Some(candidate.path.to_string_lossy().to_string()),
        discovered_executables: candidate.discovered,
        missing_executables: candidate.missing,
        argyll_version: candidate.argyll_version,
        last_validation_time: Some(iso_timestamp()),
    }
}

fn preferred_version_probe(discovered: &[String]) -> Option<&str> {
    discovered
        .iter()
        .find(|item| item.as_str() == "targen")
        .map(String::as_str)
        .or_else(|| discovered.first().map(String::as_str))
}

fn probe_argyll_version(executable_path: &Path) -> Option<String> {
    let output = Command::new(executable_path).arg("-?").output().ok()?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    extract_version_from_output(&format!("{stdout}\n{stderr}"))
}

fn extract_version_from_output(output: &str) -> Option<String> {
    for line in output.lines() {
        let marker = "Version ";
        let Some(index) = line.find(marker) else {
            continue;
        };

        let version = line[index + marker.len()..]
            .chars()
            .take_while(|character| {
                character.is_ascii_alphanumeric() || matches!(character, '.' | '-' | '_')
            })
            .collect::<String>();

        if !version.is_empty() {
            return Some(version);
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::EngineConfig;
    use std::ffi::OsStr;
    use std::fs;
    use tempfile::tempdir;

    fn config_with_search_roots(override_path: Option<String>, roots: Vec<String>) -> EngineConfig {
        EngineConfig {
            app_support_path: "/tmp/argyllux-tests/app-support".to_string(),
            database_path: "/tmp/argyllux-tests/app.sqlite".to_string(),
            log_path: "/tmp/argyllux-tests/app.log".to_string(),
            argyll_override_path: override_path,
            additional_search_roots: roots,
        }
    }

    fn make_candidate(dir: &Path, executables: &[&str]) {
        fs::create_dir_all(dir).unwrap();
        for executable in executables {
            let path = dir.join(executable);
            fs::write(&path, "#!/bin/sh\nexit 0\n").unwrap();
        }
    }

    #[test]
    fn discovery_prefers_override_before_path() {
        let temp = tempdir().unwrap();
        let override_dir = temp.path().join("override/bin");
        let path_dir = temp.path().join("path/bin");
        make_candidate(&override_dir, REQUIRED_EXECUTABLES);
        make_candidate(&path_dir, &["targen", "printtarg"]);

        let config =
            config_with_search_roots(Some(override_dir.to_string_lossy().to_string()), Vec::new());
        let path_value = OsStr::new(path_dir.to_string_lossy().as_ref()).to_os_string();
        let status = discover_toolchain_internal(&config, Some(path_value), &[]);

        assert_eq!(status.state, ToolchainState::Ready);
        assert_eq!(
            status.resolved_install_path.as_deref(),
            Some(override_dir.to_string_lossy().as_ref())
        );
    }

    #[test]
    fn discovery_reports_partial_for_best_candidate() {
        let temp = tempdir().unwrap();
        let partial_dir = temp.path().join("partial/bin");
        make_candidate(
            &partial_dir,
            &["targen", "printtarg", "chartread", "colprof"],
        );

        let config =
            config_with_search_roots(None, vec![partial_dir.to_string_lossy().to_string()]);
        let status = discover_toolchain_internal(&config, None, &[]);

        assert_eq!(status.state, ToolchainState::Partial);
        assert_eq!(status.discovered_executables.len(), 4);
        assert!(status.missing_executables.contains(&"spotread".to_string()));
    }

    #[test]
    fn discovery_reports_not_found_when_no_candidates_match() {
        let temp = tempdir().unwrap();
        let empty_dir = temp.path().join("empty");
        fs::create_dir_all(&empty_dir).unwrap();

        let config = config_with_search_roots(None, vec![empty_dir.to_string_lossy().to_string()]);
        let status = discover_toolchain_internal(&config, None, &[]);

        assert_eq!(status.state, ToolchainState::NotFound);
        assert!(status.discovered_executables.is_empty());
        assert_eq!(status.missing_executables.len(), REQUIRED_EXECUTABLES.len());
    }

    #[test]
    fn extract_version_ignores_warning_lines() {
        let output = r#"
2026-04-19 18:45:12.846 targen[96970:54110597] Failure on line 688 in function id scheduleApplicationNotification(LSNotificationCode, NSWorkspaceNotificationCenter *): noErr == _LSModifyNotification(notificationID, 1, &code, 0, NULL, NULL, NULL)
Generate Target deviceb test chart color values, Version 3.5.0
Author: Graeme W. Gill, licensed under the AGPL Version 3
"#;

        assert_eq!(
            extract_version_from_output(output).as_deref(),
            Some("3.5.0")
        );
    }
}
