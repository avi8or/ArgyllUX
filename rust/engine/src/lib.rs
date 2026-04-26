mod db;
mod diagnostics;
mod logging;
mod model;
mod runner;
mod support;
mod toolchain;

pub use model::{
    ActiveWorkItem, AppHealth, ArtifactKind, BootstrapStatus, ColorantFamily, CommandRunState,
    CommandStream, CreateNewProfileDraftInput, CreatePaperInput, CreatePrinterInput,
    CreatePrinterPaperPresetInput, DashboardSnapshot, DeleteResult, DiagnosticCategory,
    DiagnosticEventFilter, DiagnosticEventInput, DiagnosticEventRecord, DiagnosticLevel,
    DiagnosticPrivacy, DiagnosticsExportOptions, DiagnosticsExportResult,
    DiagnosticsRetentionStatus, DiagnosticsSummary, EngineConfig, InstrumentConnectionState,
    InstrumentStatus, JobArtifactRecord, JobCommandEventRecord, JobCommandRecord, LogEntry,
    MeasurementMode, MeasurementStatusRecord, NewProfileContextRecord, NewProfileJobDetail,
    PaperRecord, PrintSettingsRecord, PrinterPaperPresetRecord, PrinterProfileRecord,
    PrinterRecord, ReviewSummaryRecord, SaveNewProfileContextInput, SavePrintSettingsInput,
    SaveTargetSettingsInput, StartMeasurementInput, TargetSettingsRecord, ToolchainState,
    ToolchainStatus, UpdatePaperInput, UpdatePrinterInput, UpdatePrinterPaperPresetInput,
    WorkflowStage, WorkflowStageState, WorkflowStageSummary,
};

use crate::model::EngineState;
use crate::runner::JobTask;
use crate::support::{
    EngineResult, ensure_runtime_paths, sanitize_optional_path, sanitize_search_roots,
};
use std::sync::RwLock;

uniffi::setup_scaffolding!("argyllux");

#[derive(uniffi::Object)]
pub struct Engine {
    state: RwLock<EngineState>,
}

impl Default for Engine {
    fn default() -> Self {
        Self::new()
    }
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
                if let Err(error) = db::prune_diagnostic_events(&sanitized_config.database_path) {
                    logging::append_log(
                        &sanitized_config.log_path,
                        "warning",
                        "engine.diagnostics",
                        format!("Diagnostics retention pruning failed: {error}"),
                    );
                }
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
                        db::DATABASE_VERSION as u32,
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

        if database_initialized
            && let Err(error) =
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

        let bootstrap_status = BootstrapStatus {
            app_support_dir_ready,
            database_initialized,
            migrations_applied,
            toolchain_status: toolchain_status.clone(),
        };

        let dashboard_snapshot = build_dashboard_snapshot(&sanitized_config);
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
        state.dashboard_snapshot = dashboard_snapshot;

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
        let dashboard_snapshot = build_dashboard_snapshot(&config);

        let mut state = self.state.write().expect("engine state lock poisoned");
        state.config = Some(config);
        state.toolchain_status = toolchain_status.clone();
        state.app_health = app_health;
        state.dashboard_snapshot = dashboard_snapshot;

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
    pub fn list_diagnostic_events(
        &self,
        filter: DiagnosticEventFilter,
    ) -> Vec<DiagnosticEventRecord> {
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
        let argyll_path_category =
            diagnostics::path_category(state.toolchain_status.resolved_install_path.as_deref());
        drop(state);

        db::get_diagnostics_summary(
            &config.database_path,
            &readiness,
            &argyll_version,
            &argyll_path_category,
        )
        .unwrap_or_else(|_| {
            fallback_diagnostics_summary(&readiness, &argyll_version, &argyll_path_category)
        })
    }

    #[uniffi::method(name = "getDashboardSnapshot")]
    pub fn get_dashboard_snapshot(&self) -> DashboardSnapshot {
        let config = self
            .state
            .read()
            .expect("engine state lock poisoned")
            .config
            .clone();

        let Some(config) = config else {
            return DashboardSnapshot::default();
        };

        let snapshot = build_dashboard_snapshot(&config);
        self.state
            .write()
            .expect("engine state lock poisoned")
            .dashboard_snapshot = snapshot.clone();
        snapshot
    }

    #[uniffi::method(name = "listPrinters")]
    pub fn list_printers(&self) -> Vec<PrinterRecord> {
        with_config(&self.state, |config| {
            db::list_printers(&config.database_path)
        })
        .unwrap_or_default()
    }

    #[uniffi::method(name = "createPrinter")]
    pub fn create_printer(&self, input: CreatePrinterInput) -> PrinterRecord {
        match with_config(&self.state, |config| {
            db::create_printer(&config.database_path, &input)
        }) {
            Ok(record) => record,
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.printers",
                    &format!("Create printer failed: {error}"),
                );
                fallback_printer_record()
            }
        }
    }

    #[uniffi::method(name = "updatePrinter")]
    pub fn update_printer(&self, input: UpdatePrinterInput) -> PrinterRecord {
        match with_config(&self.state, |config| {
            db::update_printer(&config.database_path, &input)
        }) {
            Ok(record) => record,
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.printers",
                    &format!("Update printer failed: {error}"),
                );
                fallback_printer_record()
            }
        }
    }

    #[uniffi::method(name = "listPapers")]
    pub fn list_papers(&self) -> Vec<PaperRecord> {
        with_config(&self.state, |config| db::list_papers(&config.database_path))
            .unwrap_or_default()
    }

    #[uniffi::method(name = "createPaper")]
    pub fn create_paper(&self, input: CreatePaperInput) -> PaperRecord {
        match with_config(&self.state, |config| {
            db::create_paper(&config.database_path, &input)
        }) {
            Ok(record) => record,
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.papers",
                    &format!("Create paper failed: {error}"),
                );
                fallback_paper_record()
            }
        }
    }

    #[uniffi::method(name = "updatePaper")]
    pub fn update_paper(&self, input: UpdatePaperInput) -> PaperRecord {
        match with_config(&self.state, |config| {
            db::update_paper(&config.database_path, &input)
        }) {
            Ok(record) => record,
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.papers",
                    &format!("Update paper failed: {error}"),
                );
                fallback_paper_record()
            }
        }
    }

    #[uniffi::method(name = "listPrinterPaperPresets")]
    pub fn list_printer_paper_presets(&self) -> Vec<PrinterPaperPresetRecord> {
        with_config(&self.state, |config| {
            db::list_printer_paper_presets(&config.database_path)
        })
        .unwrap_or_default()
    }

    #[uniffi::method(name = "createPrinterPaperPreset")]
    pub fn create_printer_paper_preset(
        &self,
        input: CreatePrinterPaperPresetInput,
    ) -> PrinterPaperPresetRecord {
        match with_config(&self.state, |config| {
            db::create_printer_paper_preset(&config.database_path, &input)
        }) {
            Ok(record) => record,
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.printer_paper_presets",
                    &format!("Create printer-paper preset failed: {error}"),
                );
                fallback_printer_paper_preset_record()
            }
        }
    }

    #[uniffi::method(name = "updatePrinterPaperPreset")]
    pub fn update_printer_paper_preset(
        &self,
        input: UpdatePrinterPaperPresetInput,
    ) -> PrinterPaperPresetRecord {
        match with_config(&self.state, |config| {
            db::update_printer_paper_preset(&config.database_path, &input)
        }) {
            Ok(record) => record,
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.printer_paper_presets",
                    &format!("Update printer-paper preset failed: {error}"),
                );
                fallback_printer_paper_preset_record()
            }
        }
    }

    #[uniffi::method(name = "listPrinterProfiles")]
    pub fn list_printer_profiles(&self) -> Vec<PrinterProfileRecord> {
        with_config(&self.state, |config| {
            db::list_printer_profiles(&config.database_path)
        })
        .unwrap_or_default()
    }

    #[uniffi::method(name = "createNewProfileDraft")]
    pub fn create_new_profile_draft(
        &self,
        input: CreateNewProfileDraftInput,
    ) -> NewProfileJobDetail {
        let result = with_config(&self.state, |config| {
            db::create_new_profile_draft(&config.database_path, &config.app_support_path, &input)
        });
        match result {
            Ok(detail) => {
                refresh_dashboard(&self.state);
                detail
            }
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.jobs",
                    &format!("Create new profile draft failed: {error}"),
                );
                fallback_job_detail("new-profile", Some(error.to_string()))
            }
        }
    }

    #[uniffi::method(name = "resolveNewProfileLaunch")]
    pub fn resolve_new_profile_launch(
        &self,
        input: CreateNewProfileDraftInput,
    ) -> NewProfileJobDetail {
        let result = with_config(&self.state, |config| {
            db::resolve_new_profile_launch(&config.database_path, &config.app_support_path, &input)
        });
        match result {
            Ok(detail) => {
                refresh_dashboard(&self.state);
                detail
            }
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.jobs",
                    &format!("Resolve new profile launch failed: {error}"),
                );
                fallback_job_detail("new-profile", Some(error.to_string()))
            }
        }
    }

    #[uniffi::method(name = "getNewProfileJobDetail")]
    pub fn get_new_profile_job_detail(&self, job_id: String) -> NewProfileJobDetail {
        match with_config(&self.state, |config| {
            db::load_new_profile_job_detail(&config.database_path, &job_id)
        }) {
            Ok(detail) => {
                refresh_dashboard(&self.state);
                detail
            }
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.jobs",
                    &format!("Load new profile job failed: {error}"),
                );
                fallback_job_detail(&job_id, Some(error.to_string()))
            }
        }
    }

    #[uniffi::method(name = "saveNewProfileContext")]
    pub fn save_new_profile_context(
        &self,
        input: SaveNewProfileContextInput,
    ) -> NewProfileJobDetail {
        match with_config(&self.state, |config| {
            db::save_new_profile_context(&config.database_path, &input)
        }) {
            Ok(detail) => {
                refresh_dashboard(&self.state);
                detail
            }
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.jobs",
                    &format!("Save New Profile context failed: {error}"),
                );
                fallback_job_detail(&input.job_id, Some(error.to_string()))
            }
        }
    }

    #[uniffi::method(name = "saveTargetSettings")]
    pub fn save_target_settings(&self, input: SaveTargetSettingsInput) -> NewProfileJobDetail {
        match with_config(&self.state, |config| {
            db::save_target_settings(&config.database_path, &input)
        }) {
            Ok(detail) => {
                refresh_dashboard(&self.state);
                detail
            }
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.jobs",
                    &format!("Save target settings failed: {error}"),
                );
                fallback_job_detail(&input.job_id, Some(error.to_string()))
            }
        }
    }

    #[uniffi::method(name = "savePrintSettings")]
    pub fn save_print_settings(&self, input: SavePrintSettingsInput) -> NewProfileJobDetail {
        match with_config(&self.state, |config| {
            db::save_print_settings(&config.database_path, &input)
        }) {
            Ok(detail) => {
                refresh_dashboard(&self.state);
                detail
            }
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.jobs",
                    &format!("Save print settings failed: {error}"),
                );
                fallback_job_detail(&input.job_id, Some(error.to_string()))
            }
        }
    }

    #[uniffi::method(name = "startGenerateTarget")]
    pub fn start_generate_target(&self, job_id: String) -> NewProfileJobDetail {
        let (config, toolchain_status) = match current_runtime_context(&self.state) {
            Some(context) => context,
            None => {
                return fallback_job_detail(
                    &job_id,
                    Some("ArgyllUX has not been bootstrapped yet.".to_string()),
                );
            }
        };
        match db::prepare_generate_target(&config.database_path, &job_id) {
            Ok(detail) => {
                runner::spawn_job_task(
                    config,
                    toolchain_status,
                    job_id.clone(),
                    JobTask::GenerateTarget,
                );
                refresh_dashboard(&self.state);
                detail
            }
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.jobs",
                    &format!("Start generate target failed: {error}"),
                );
                fallback_job_detail(&job_id, Some(error.to_string()))
            }
        }
    }

    #[uniffi::method(name = "markNewProfilePrinted")]
    pub fn mark_new_profile_printed(&self, job_id: String) -> NewProfileJobDetail {
        match with_config(&self.state, |config| {
            db::mark_new_profile_printed(&config.database_path, &job_id)
        }) {
            Ok(detail) => {
                refresh_dashboard(&self.state);
                detail
            }
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.jobs",
                    &format!("Mark printed failed: {error}"),
                );
                fallback_job_detail(&job_id, Some(error.to_string()))
            }
        }
    }

    #[uniffi::method(name = "markNewProfileReadyToMeasure")]
    pub fn mark_new_profile_ready_to_measure(&self, job_id: String) -> NewProfileJobDetail {
        match with_config(&self.state, |config| {
            db::mark_new_profile_ready_to_measure(&config.database_path, &job_id)
        }) {
            Ok(detail) => {
                refresh_dashboard(&self.state);
                detail
            }
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.jobs",
                    &format!("Mark ready to measure failed: {error}"),
                );
                fallback_job_detail(&job_id, Some(error.to_string()))
            }
        }
    }

    #[uniffi::method(name = "startMeasurement")]
    pub fn start_measurement(&self, input: StartMeasurementInput) -> NewProfileJobDetail {
        let (config, toolchain_status) = match current_runtime_context(&self.state) {
            Some(context) => context,
            None => {
                return fallback_job_detail(
                    &input.job_id,
                    Some("ArgyllUX has not been bootstrapped yet.".to_string()),
                );
            }
        };
        match db::prepare_measurement(&config.database_path, &input) {
            Ok(detail) => {
                runner::spawn_job_task(
                    config,
                    toolchain_status,
                    input.job_id.clone(),
                    JobTask::MeasureTarget,
                );
                refresh_dashboard(&self.state);
                detail
            }
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.jobs",
                    &format!("Start measurement failed: {error}"),
                );
                fallback_job_detail(&input.job_id, Some(error.to_string()))
            }
        }
    }

    #[uniffi::method(name = "startBuildProfile")]
    pub fn start_build_profile(&self, job_id: String) -> NewProfileJobDetail {
        let (config, toolchain_status) = match current_runtime_context(&self.state) {
            Some(context) => context,
            None => {
                return fallback_job_detail(
                    &job_id,
                    Some("ArgyllUX has not been bootstrapped yet.".to_string()),
                );
            }
        };
        match db::prepare_build_profile(&config.database_path, &job_id) {
            Ok(detail) => {
                runner::spawn_job_task(
                    config,
                    toolchain_status,
                    job_id.clone(),
                    JobTask::BuildProfile,
                );
                refresh_dashboard(&self.state);
                detail
            }
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.jobs",
                    &format!("Start build profile failed: {error}"),
                );
                fallback_job_detail(&job_id, Some(error.to_string()))
            }
        }
    }

    #[uniffi::method(name = "publishNewProfile")]
    pub fn publish_new_profile(&self, job_id: String) -> NewProfileJobDetail {
        match with_config(&self.state, |config| {
            db::publish_new_profile(&config.database_path, &job_id)
        }) {
            Ok(detail) => {
                refresh_dashboard(&self.state);
                detail
            }
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.jobs",
                    &format!("Publish profile failed: {error}"),
                );
                fallback_job_detail(&job_id, Some(error.to_string()))
            }
        }
    }

    #[uniffi::method(name = "deleteNewProfileJob")]
    pub fn delete_new_profile_job(&self, job_id: String) -> DeleteResult {
        match with_config(&self.state, |config| {
            db::delete_new_profile_job(&config.database_path, &job_id)
        }) {
            Ok(result) => {
                refresh_dashboard(&self.state);
                result
            }
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.jobs",
                    &format!("Delete new profile job failed: {error}"),
                );
                DeleteResult {
                    success: false,
                    message: error.to_string(),
                }
            }
        }
    }

    #[uniffi::method(name = "deletePrinterProfile")]
    pub fn delete_printer_profile(&self, profile_id: String) -> DeleteResult {
        match with_config(&self.state, |config| {
            db::delete_printer_profile(&config.database_path, &profile_id)
        }) {
            Ok(result) => {
                refresh_dashboard(&self.state);
                result
            }
            Err(error) => {
                log_config_error(
                    &self.state,
                    "engine.profiles",
                    &format!("Delete printer profile failed: {error}"),
                );
                DeleteResult {
                    success: false,
                    message: error.to_string(),
                }
            }
        }
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
                "Install the missing ArgyllCMS tools before starting a new profile workflow."
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

fn build_dashboard_snapshot(config: &EngineConfig) -> DashboardSnapshot {
    db::load_dashboard_snapshot(&config.database_path).unwrap_or_default()
}

fn refresh_dashboard(state: &RwLock<EngineState>) {
    let config = state
        .read()
        .expect("engine state lock poisoned")
        .config
        .clone();

    if let Some(config) = config {
        let snapshot = build_dashboard_snapshot(&config);
        state
            .write()
            .expect("engine state lock poisoned")
            .dashboard_snapshot = snapshot;
    }
}

fn with_config<T>(
    state: &RwLock<EngineState>,
    op: impl FnOnce(&EngineConfig) -> EngineResult<T>,
) -> EngineResult<T> {
    let config = state
        .read()
        .expect("engine state lock poisoned")
        .config
        .clone()
        .ok_or_else(|| {
            Box::<dyn std::error::Error + Send + Sync>::from(
                "ArgyllUX has not been bootstrapped yet.",
            )
        })?;
    op(&config)
}

fn current_runtime_context(state: &RwLock<EngineState>) -> Option<(EngineConfig, ToolchainStatus)> {
    let state = state.read().expect("engine state lock poisoned");
    let config = state.config.clone()?;
    Some((config, state.toolchain_status.clone()))
}

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

fn fallback_printer_record() -> PrinterRecord {
    PrinterRecord {
        id: String::new(),
        manufacturer: String::new(),
        model: String::new(),
        nickname: String::new(),
        transport_style: String::new(),
        colorant_family: ColorantFamily::Cmyk,
        channel_count: 4,
        channel_labels: Vec::new(),
        supported_media_settings: Vec::new(),
        supported_quality_modes: Vec::new(),
        monochrome_path_notes: String::new(),
        notes: String::new(),
        display_name: String::new(),
        created_at: String::new(),
        updated_at: String::new(),
    }
}

fn fallback_paper_record() -> PaperRecord {
    PaperRecord {
        id: String::new(),
        manufacturer: String::new(),
        paper_line: String::new(),
        surface_class: String::new(),
        basis_weight_value: String::new(),
        basis_weight_unit: crate::model::PaperWeightUnit::Unspecified,
        thickness_value: String::new(),
        thickness_unit: crate::model::PaperThicknessUnit::Unspecified,
        surface_texture: String::new(),
        base_material: String::new(),
        media_color: String::new(),
        opacity: String::new(),
        whiteness: String::new(),
        oba_content: String::new(),
        ink_compatibility: String::new(),
        notes: String::new(),
        display_name: String::new(),
        created_at: String::new(),
        updated_at: String::new(),
    }
}

fn fallback_printer_paper_preset_record() -> PrinterPaperPresetRecord {
    PrinterPaperPresetRecord {
        id: String::new(),
        printer_id: String::new(),
        paper_id: String::new(),
        label: String::new(),
        print_path: String::new(),
        media_setting: String::new(),
        quality_mode: String::new(),
        total_ink_limit_percent: None,
        black_ink_limit_percent: None,
        notes: String::new(),
        display_name: String::new(),
        created_at: String::new(),
        updated_at: String::new(),
    }
}

fn fallback_job_detail(job_id: &str, latest_error: Option<String>) -> NewProfileJobDetail {
    NewProfileJobDetail {
        id: job_id.to_string(),
        title: "New Profile".to_string(),
        status: "failed".to_string(),
        stage: WorkflowStage::Failed,
        next_action: "Review the technical details".to_string(),
        profile_name: String::new(),
        printer_name: String::new(),
        paper_name: String::new(),
        workspace_path: String::new(),
        printer: None,
        paper: None,
        context: NewProfileContextRecord {
            printer_paper_preset_id: None,
            print_path: String::new(),
            media_setting: String::new(),
            quality_mode: String::new(),
            colorant_family: ColorantFamily::Cmyk,
            channel_count: 4,
            channel_labels: Vec::new(),
            total_ink_limit_percent: None,
            black_ink_limit_percent: None,
            print_path_notes: String::new(),
            measurement_notes: String::new(),
            measurement_observer: "1931_2".to_string(),
            measurement_illuminant: "D50".to_string(),
            measurement_mode: MeasurementMode::Strip,
        },
        target_settings: TargetSettingsRecord {
            patch_count: 836,
            improve_neutrals: false,
            use_existing_profile_to_help_target_planning: false,
            planning_profile_id: None,
            planning_profile_name: None,
        },
        print_settings: PrintSettingsRecord {
            print_without_color_management: true,
            drying_time_minutes: 120,
            printed_at: None,
            drying_ready_at: None,
        },
        measurement: MeasurementStatusRecord {
            measurement_source_path: None,
            scan_file_path: None,
            has_measurement_checkpoint: false,
        },
        latest_error,
        published_profile_id: None,
        review: None,
        stage_timeline: vec![
            WorkflowStageSummary {
                stage: WorkflowStage::Context,
                title: "Context".to_string(),
                state: WorkflowStageState::Upcoming,
            },
            WorkflowStageSummary {
                stage: WorkflowStage::Target,
                title: "Target".to_string(),
                state: WorkflowStageState::Upcoming,
            },
            WorkflowStageSummary {
                stage: WorkflowStage::Print,
                title: "Print".to_string(),
                state: WorkflowStageState::Upcoming,
            },
            WorkflowStageSummary {
                stage: WorkflowStage::Drying,
                title: "Drying".to_string(),
                state: WorkflowStageState::Upcoming,
            },
            WorkflowStageSummary {
                stage: WorkflowStage::Measure,
                title: "Measure".to_string(),
                state: WorkflowStageState::Upcoming,
            },
            WorkflowStageSummary {
                stage: WorkflowStage::Build,
                title: "Build".to_string(),
                state: WorkflowStageState::Upcoming,
            },
            WorkflowStageSummary {
                stage: WorkflowStage::Review,
                title: "Review".to_string(),
                state: WorkflowStageState::Blocked,
            },
            WorkflowStageSummary {
                stage: WorkflowStage::Publish,
                title: "Publish".to_string(),
                state: WorkflowStageState::Upcoming,
            },
        ],
        artifacts: Vec::new(),
        commands: Vec::new(),
        is_command_running: false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn build_config(root: &std::path::Path) -> EngineConfig {
        EngineConfig {
            app_support_path: root
                .join("Application Support/ArgyllUX")
                .to_string_lossy()
                .to_string(),
            database_path: root
                .join("Application Support/ArgyllUX/engine.sqlite")
                .to_string_lossy()
                .to_string(),
            log_path: root.join("Logs/argyllux.log").to_string_lossy().to_string(),
            argyll_override_path: None,
            additional_search_roots: Vec::new(),
        }
    }

    #[test]
    fn bootstrap_creates_directories_and_database() {
        let temp = tempdir().unwrap();
        let engine = Engine::new();
        let status = engine.bootstrap(build_config(temp.path()));

        assert!(status.app_support_dir_ready);
        assert!(status.database_initialized);
    }

    #[test]
    fn bridge_records_lists_and_summarizes_diagnostic_events() {
        let temp = tempfile::tempdir().unwrap();
        let engine = Engine::new();
        let config = EngineConfig {
            app_support_path: temp
                .path()
                .join("app-support")
                .to_string_lossy()
                .to_string(),
            database_path: temp
                .path()
                .join("app-support/argyllux.sqlite")
                .to_string_lossy()
                .to_string(),
            log_path: temp
                .path()
                .join("logs/engine.log")
                .to_string_lossy()
                .to_string(),
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

    #[test]
    fn create_new_profile_draft_updates_dashboard_snapshot() {
        let temp = tempdir().unwrap();
        let engine = Engine::new();
        engine.bootstrap(build_config(temp.path()));

        let detail = engine.create_new_profile_draft(CreateNewProfileDraftInput {
            profile_name: Some("P900 Rag v1".to_string()),
            printer_id: None,
            paper_id: None,
        });
        let snapshot = engine.get_dashboard_snapshot();

        assert_eq!(detail.stage, WorkflowStage::Context);
        assert_eq!(snapshot.jobs_count, 1);
        assert_eq!(snapshot.active_work_items[0].id, detail.id);
    }

    #[test]
    fn set_toolchain_path_updates_cached_state() {
        let temp = tempdir().unwrap();
        let engine = Engine::new();
        engine.bootstrap(build_config(temp.path()));

        let status = engine.set_toolchain_path(Some("/Applications/ArgyllCMS".to_string()));
        assert!(matches!(
            status.state,
            ToolchainState::Ready | ToolchainState::Partial | ToolchainState::NotFound
        ));
    }
}
