mod db;
mod logging;
mod model;
mod support;
mod toolchain;

pub use model::{
    AppHealth, BootstrapStatus, EngineConfig, LogEntry, ToolchainState, ToolchainStatus,
};

use crate::model::EngineState;
use crate::support::{ensure_runtime_paths, sanitize_optional_path, sanitize_search_roots};
use std::sync::RwLock;

uniffi::setup_scaffolding!("argyllux");

#[derive(uniffi::Object)]
pub struct Engine {
    state: RwLock<EngineState>,
}

#[uniffi::export]
impl Engine {
    #[uniffi::constructor(name = "new")]
    pub fn new() -> Self {
        Self {
            state: RwLock::new(EngineState::default()),
        }
    }

    pub fn bootstrap(&self, config: EngineConfig) -> BootstrapStatus {
        let mut sanitized_config = sanitize_config(config);
        let app_support_dir_ready = ensure_runtime_paths(
            &sanitized_config.app_support_path,
            &sanitized_config.database_path,
            &sanitized_config.log_path,
        );

        logging::append_log(
            &sanitized_config.log_path,
            "info",
            "engine.bootstrap",
            "Starting ArgyllUX bootstrap.",
        );

        let mut database_initialized = false;
        let mut migrations_applied = false;
        let mut persisted_override_path = None;

        match db::initialize_database(&sanitized_config) {
            Ok(status) => {
                database_initialized = status.initialized;
                migrations_applied = status.migrations_applied;
                persisted_override_path = status.persisted_override_path;
            }
            Err(error) => {
                logging::append_log(
                    &sanitized_config.log_path,
                    "error",
                    "engine.bootstrap",
                    format!("Database initialization failed: {error}"),
                );
            }
        }

        if sanitized_config.argyll_override_path.is_none() {
            sanitized_config.argyll_override_path = persisted_override_path;
        }

        let toolchain_status = toolchain::discover_toolchain(&sanitized_config);

        if database_initialized {
            if let Err(error) =
                db::persist_toolchain_status(&sanitized_config.database_path, &toolchain_status)
            {
                logging::append_log(
                    &sanitized_config.log_path,
                    "warning",
                    "engine.bootstrap",
                    format!("Toolchain status cache write failed: {error}"),
                );
                database_initialized = false;
            }
        }

        let bootstrap_status = BootstrapStatus {
            app_support_dir_ready,
            database_initialized,
            migrations_applied,
            toolchain_status: toolchain_status.clone(),
        };

        let app_health = build_app_health(
            &sanitized_config,
            &bootstrap_status,
            sanitized_config.argyll_override_path.as_deref(),
        );

        logging::append_log(
            &sanitized_config.log_path,
            "info",
            "engine.bootstrap",
            format!(
                "Bootstrap completed with toolchain state {:?}.",
                bootstrap_status.toolchain_status.state
            ),
        );

        let mut state = self.state.write().expect("engine state lock poisoned");
        state.config = Some(sanitized_config);
        state.bootstrap_status = Some(bootstrap_status.clone());
        state.toolchain_status = toolchain_status;
        state.app_health = app_health;

        bootstrap_status
    }

    #[uniffi::method(name = "getToolchainStatus")]
    pub fn get_toolchain_status(&self) -> ToolchainStatus {
        self.state
            .read()
            .expect("engine state lock poisoned")
            .toolchain_status
            .clone()
    }

    #[uniffi::method(name = "setToolchainPath")]
    pub fn set_toolchain_path(&self, path: Option<String>) -> ToolchainStatus {
        let (mut config, bootstrap_status) = {
            let state = self.state.read().expect("engine state lock poisoned");
            match state.config.clone() {
                Some(config) => (config, state.bootstrap_status.clone()),
                None => return ToolchainStatus::default(),
            }
        };

        config.argyll_override_path = sanitize_optional_path(path);

        logging::append_log(
            &config.log_path,
            "info",
            "engine.toolchain",
            "Refreshing Argyll toolchain configuration.",
        );

        if let Err(error) = db::persist_toolchain_override(
            &config.database_path,
            config.argyll_override_path.as_deref(),
        ) {
            logging::append_log(
                &config.log_path,
                "warning",
                "engine.toolchain",
                format!("Toolchain override write failed: {error}"),
            );
        }

        let toolchain_status = toolchain::discover_toolchain(&config);

        if let Err(error) = db::persist_toolchain_status(&config.database_path, &toolchain_status) {
            logging::append_log(
                &config.log_path,
                "warning",
                "engine.toolchain",
                format!("Toolchain status cache write failed: {error}"),
            );
        }

        let bootstrap_status = bootstrap_status.unwrap_or(BootstrapStatus {
            app_support_dir_ready: true,
            database_initialized: true,
            migrations_applied: false,
            toolchain_status: toolchain_status.clone(),
        });

        let app_health = build_app_health(
            &config,
            &BootstrapStatus {
                toolchain_status: toolchain_status.clone(),
                ..bootstrap_status
            },
            config.argyll_override_path.as_deref(),
        );

        let mut state = self.state.write().expect("engine state lock poisoned");
        state.config = Some(config);
        state.toolchain_status = toolchain_status.clone();
        state.app_health = app_health;

        toolchain_status
    }

    #[uniffi::method(name = "getAppHealth")]
    pub fn get_app_health(&self) -> AppHealth {
        self.state
            .read()
            .expect("engine state lock poisoned")
            .app_health
            .clone()
    }

    #[uniffi::method(name = "getRecentLogs")]
    pub fn get_recent_logs(&self, limit: u32) -> Vec<LogEntry> {
        let config = self
            .state
            .read()
            .expect("engine state lock poisoned")
            .config
            .clone();

        config
            .map(|config| logging::read_recent_logs(&config.log_path, limit as usize))
            .unwrap_or_default()
    }
}

fn sanitize_config(config: EngineConfig) -> EngineConfig {
    EngineConfig {
        app_support_path: config.app_support_path.trim().to_string(),
        database_path: config.database_path.trim().to_string(),
        log_path: config.log_path.trim().to_string(),
        argyll_override_path: sanitize_optional_path(config.argyll_override_path),
        additional_search_roots: sanitize_search_roots(config.additional_search_roots),
    }
}

fn build_app_health(
    config: &EngineConfig,
    bootstrap_status: &BootstrapStatus,
    requested_override: Option<&str>,
) -> AppHealth {
    let mut blocking_issues = Vec::new();
    let mut warnings = Vec::new();

    if !bootstrap_status.app_support_dir_ready {
        blocking_issues.push("ArgyllUX could not prepare its support directories.".to_string());
    }

    if !bootstrap_status.database_initialized {
        blocking_issues.push("ArgyllUX could not initialize its SQLite storage.".to_string());
    }

    match bootstrap_status.toolchain_status.state {
        ToolchainState::Ready => {}
        ToolchainState::Partial => {
            blocking_issues.push(format!(
                "ArgyllCMS is missing required tools: {}.",
                bootstrap_status
                    .toolchain_status
                    .missing_executables
                    .join(", ")
            ));
            warnings.push(
                "Only health and setup surfaces are available until the missing tools are installed."
                    .to_string(),
            );
        }
        ToolchainState::NotFound => {
            blocking_issues.push(
                "ArgyllCMS was not found in the configured path, common install locations, or PATH."
                    .to_string(),
            );
        }
    }

    if let Some(override_path) = requested_override {
        let resolved_path = bootstrap_status
            .toolchain_status
            .resolved_install_path
            .as_deref()
            .unwrap_or_default();

        if resolved_path.is_empty() {
            warnings.push(format!(
                "The configured Argyll path could not be validated: {override_path}"
            ));
        } else if resolved_path != override_path {
            warnings.push(format!(
                "The configured Argyll path is unavailable. Using the discovered install at {resolved_path}."
            ));
        }
    }

    if bootstrap_status.toolchain_status.state == ToolchainState::Ready {
        warnings.push(format!("Storage location: {}", config.app_support_path));
    }

    let readiness = if blocking_issues.is_empty() {
        "ready"
    } else if bootstrap_status.toolchain_status.state == ToolchainState::Partial {
        "attention"
    } else {
        "blocked"
    };

    AppHealth {
        readiness: readiness.to_string(),
        blocking_issues,
        warnings,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;
    use std::fs;
    use tempfile::tempdir;

    fn make_fake_argyll(dir: &std::path::Path, executables: &[&str]) {
        fs::create_dir_all(dir).unwrap();
        for executable in executables {
            fs::write(dir.join(executable), "#!/bin/sh\nexit 0\n").unwrap();
        }
    }

    fn build_config(root: &std::path::Path, override_path: Option<String>) -> EngineConfig {
        EngineConfig {
            app_support_path: root
                .join("Application Support/ArgyllUX")
                .to_string_lossy()
                .to_string(),
            database_path: root
                .join("Application Support/ArgyllUX/argyllux.sqlite")
                .to_string_lossy()
                .to_string(),
            log_path: root.join("Logs/argyllux.log").to_string_lossy().to_string(),
            argyll_override_path: override_path,
            additional_search_roots: Vec::new(),
        }
    }

    #[test]
    fn bootstrap_creates_directories_and_database() {
        let temp = tempdir().unwrap();
        let bin_dir = temp.path().join("Argyll/bin");
        make_fake_argyll(&bin_dir, toolchain::required_executables());

        let engine = Engine::new();
        let status = engine.bootstrap(build_config(
            temp.path(),
            Some(bin_dir.to_string_lossy().to_string()),
        ));

        assert!(status.app_support_dir_ready);
        assert!(status.database_initialized);
        assert!(status.migrations_applied);
        assert_eq!(status.toolchain_status.state, ToolchainState::Ready);

        let database_path = temp
            .path()
            .join("Application Support/ArgyllUX/argyllux.sqlite");
        assert!(database_path.exists());

        let connection = Connection::open(database_path).unwrap();
        let table_count: i64 = connection
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name IN ('app_settings', 'toolchain_status_cache', 'print_configurations', 'jobs', 'artifacts')",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(table_count, 5);
    }

    #[test]
    fn bootstrap_is_idempotent() {
        let temp = tempdir().unwrap();
        let bin_dir = temp.path().join("Argyll/bin");
        make_fake_argyll(&bin_dir, toolchain::required_executables());
        let config = build_config(temp.path(), Some(bin_dir.to_string_lossy().to_string()));

        let engine = Engine::new();
        let first = engine.bootstrap(config.clone());
        let second = engine.bootstrap(config);

        assert!(first.migrations_applied);
        assert!(!second.migrations_applied);
        assert_eq!(second.toolchain_status.state, ToolchainState::Ready);
    }

    #[test]
    fn set_toolchain_path_updates_cached_state() {
        let temp = tempdir().unwrap();
        let partial_dir = temp.path().join("Argyll Partial/bin");
        make_fake_argyll(&partial_dir, &["targen", "printtarg"]);

        let engine = Engine::new();
        engine.bootstrap(build_config(temp.path(), None));
        let status = engine.set_toolchain_path(Some(partial_dir.to_string_lossy().to_string()));
        let cached_status = engine.get_toolchain_status();
        let database_path = temp
            .path()
            .join("Application Support/ArgyllUX/argyllux.sqlite");
        let connection = Connection::open(database_path).unwrap();
        let persisted_override: String = connection
            .query_row(
                "SELECT value FROM app_settings WHERE key = 'toolchain.override_path'",
                [],
                |row| row.get(0),
            )
            .unwrap();

        assert_eq!(cached_status.state, status.state);
        assert_eq!(
            persisted_override,
            partial_dir.to_string_lossy().to_string()
        );
        assert!(status.last_validation_time.is_some());
    }
}
