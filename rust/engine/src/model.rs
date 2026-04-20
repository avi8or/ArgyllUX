use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum ToolchainState {
    Ready,
    Partial,
    NotFound,
}

#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
pub struct EngineConfig {
    pub app_support_path: String,
    pub database_path: String,
    pub log_path: String,
    pub argyll_override_path: Option<String>,
    pub additional_search_roots: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
pub struct ToolchainStatus {
    pub state: ToolchainState,
    pub resolved_install_path: Option<String>,
    pub discovered_executables: Vec<String>,
    pub missing_executables: Vec<String>,
    pub last_validation_time: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
pub struct BootstrapStatus {
    pub app_support_dir_ready: bool,
    pub database_initialized: bool,
    pub migrations_applied: bool,
    pub toolchain_status: ToolchainStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
pub struct AppHealth {
    pub readiness: String,
    pub blocking_issues: Vec<String>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
pub struct LogEntry {
    pub timestamp: String,
    pub level: String,
    pub message: String,
    pub source: String,
}

#[derive(Debug, Clone)]
pub(crate) struct EngineState {
    pub config: Option<EngineConfig>,
    pub bootstrap_status: Option<BootstrapStatus>,
    pub app_health: AppHealth,
    pub toolchain_status: ToolchainStatus,
}

impl Default for ToolchainStatus {
    fn default() -> Self {
        Self {
            state: ToolchainState::NotFound,
            resolved_install_path: None,
            discovered_executables: Vec::new(),
            missing_executables: crate::toolchain::required_executables()
                .iter()
                .map(|item| (*item).to_string())
                .collect(),
            last_validation_time: None,
        }
    }
}

impl Default for AppHealth {
    fn default() -> Self {
        Self {
            readiness: "blocked".to_string(),
            blocking_issues: vec!["ArgyllUX has not been bootstrapped yet.".to_string()],
            warnings: Vec::new(),
        }
    }
}

impl Default for EngineState {
    fn default() -> Self {
        Self {
            config: None,
            bootstrap_status: None,
            app_health: AppHealth::default(),
            toolchain_status: ToolchainStatus::default(),
        }
    }
}
