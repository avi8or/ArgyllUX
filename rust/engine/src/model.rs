use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum ToolchainState {
    Ready,
    Partial,
    NotFound,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum InstrumentConnectionState {
    Connected,
    Disconnected,
    Attention,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum WorkflowStage {
    Context,
    Target,
    Print,
    Drying,
    Measure,
    Build,
    Review,
    Publish,
    Completed,
    Blocked,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum WorkflowStageState {
    Completed,
    Current,
    Upcoming,
    Blocked,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum MeasurementMode {
    Strip,
    Patch,
    ScanFile,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum ColorantFamily {
    GrayK,
    Rgb,
    Cmy,
    Cmyk,
    ExtendedN,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum PaperWeightUnit {
    Unspecified,
    Gsm,
    Lb,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum PaperThicknessUnit {
    Unspecified,
    Mil,
    Mm,
    Micron,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum CommandRunState {
    Running,
    Succeeded,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum CommandStream {
    Stdout,
    Stderr,
    System,
}

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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum ArtifactKind {
    Ti1,
    Ti2,
    PrintableChart,
    ChartTemplate,
    Measurement,
    IccProfile,
    Verification,
    Diagnostic,
    Working,
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
    pub argyll_version: Option<String>,
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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct InstrumentStatus {
    pub state: InstrumentConnectionState,
    pub label: String,
    pub detail: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct ActiveWorkItem {
    pub id: String,
    pub title: String,
    pub next_action: String,
    pub kind: String,
    pub stage: WorkflowStage,
    pub profile_name: String,
    pub printer_name: String,
    pub paper_name: String,
    pub status: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, uniffi::Record)]
pub struct DashboardSnapshot {
    pub active_work_items: Vec<ActiveWorkItem>,
    pub jobs_count: u32,
    pub alerts_count: u32,
    pub instrument_status: InstrumentStatus,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct LogEntry {
    pub timestamp: String,
    pub level: String,
    pub message: String,
    pub source: String,
}

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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct DeleteResult {
    pub success: bool,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct PrinterRecord {
    pub id: String,
    pub manufacturer: String,
    pub model: String,
    pub nickname: String,
    pub transport_style: String,
    pub colorant_family: ColorantFamily,
    pub channel_count: u32,
    pub channel_labels: Vec<String>,
    pub supported_media_settings: Vec<String>,
    pub supported_quality_modes: Vec<String>,
    pub monochrome_path_notes: String,
    pub notes: String,
    pub display_name: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct PaperRecord {
    pub id: String,
    pub manufacturer: String,
    pub paper_line: String,
    pub surface_class: String,
    pub basis_weight_value: String,
    pub basis_weight_unit: PaperWeightUnit,
    pub thickness_value: String,
    pub thickness_unit: PaperThicknessUnit,
    pub surface_texture: String,
    pub base_material: String,
    pub media_color: String,
    pub opacity: String,
    pub whiteness: String,
    pub oba_content: String,
    pub ink_compatibility: String,
    pub notes: String,
    pub display_name: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct PrinterPaperPresetRecord {
    pub id: String,
    pub printer_id: String,
    pub paper_id: String,
    pub label: String,
    pub print_path: String,
    pub media_setting: String,
    pub quality_mode: String,
    pub total_ink_limit_percent: Option<u32>,
    pub black_ink_limit_percent: Option<u32>,
    pub notes: String,
    pub display_name: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct PrinterProfileRecord {
    pub id: String,
    pub name: String,
    pub printer_name: String,
    pub paper_name: String,
    pub context_status: String,
    pub profile_path: String,
    pub measurement_path: String,
    pub print_settings: String,
    pub verified_against_file: String,
    pub result: String,
    pub last_verification_date: Option<String>,
    pub created_from_job_id: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct WorkflowStageSummary {
    pub stage: WorkflowStage,
    pub title: String,
    pub state: WorkflowStageState,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct JobArtifactRecord {
    pub id: String,
    pub stage: WorkflowStage,
    pub kind: ArtifactKind,
    pub label: String,
    pub status: String,
    pub path: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct JobCommandEventRecord {
    pub id: String,
    pub command_id: String,
    pub stream: CommandStream,
    pub line_number: u32,
    pub message: String,
    pub timestamp: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct JobCommandRecord {
    pub id: String,
    pub stage: WorkflowStage,
    pub label: String,
    pub argv: Vec<String>,
    pub state: CommandRunState,
    pub exit_code: Option<i32>,
    pub started_at: Option<String>,
    pub finished_at: Option<String>,
    pub events: Vec<JobCommandEventRecord>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct NewProfileContextRecord {
    pub printer_paper_preset_id: Option<String>,
    pub print_path: String,
    pub media_setting: String,
    pub quality_mode: String,
    pub colorant_family: ColorantFamily,
    pub channel_count: u32,
    pub channel_labels: Vec<String>,
    pub total_ink_limit_percent: Option<u32>,
    pub black_ink_limit_percent: Option<u32>,
    pub print_path_notes: String,
    pub measurement_notes: String,
    pub measurement_observer: String,
    pub measurement_illuminant: String,
    pub measurement_mode: MeasurementMode,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct TargetSettingsRecord {
    pub patch_count: u32,
    pub improve_neutrals: bool,
    pub use_existing_profile_to_help_target_planning: bool,
    pub planning_profile_id: Option<String>,
    pub planning_profile_name: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct PrintSettingsRecord {
    pub print_without_color_management: bool,
    pub drying_time_minutes: u32,
    pub printed_at: Option<String>,
    pub drying_ready_at: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct MeasurementStatusRecord {
    pub measurement_source_path: Option<String>,
    pub scan_file_path: Option<String>,
    pub has_measurement_checkpoint: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record)]
pub struct ReviewSummaryRecord {
    pub result: String,
    pub verified_against_file: String,
    pub print_settings: String,
    pub last_verification_date: Option<String>,
    pub average_de00: Option<f64>,
    pub maximum_de00: Option<f64>,
    pub notes: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record)]
pub struct NewProfileJobDetail {
    pub id: String,
    pub title: String,
    pub status: String,
    pub stage: WorkflowStage,
    pub next_action: String,
    pub profile_name: String,
    pub printer_name: String,
    pub paper_name: String,
    pub workspace_path: String,
    pub printer: Option<PrinterRecord>,
    pub paper: Option<PaperRecord>,
    pub context: NewProfileContextRecord,
    pub target_settings: TargetSettingsRecord,
    pub print_settings: PrintSettingsRecord,
    pub measurement: MeasurementStatusRecord,
    pub latest_error: Option<String>,
    pub published_profile_id: Option<String>,
    pub review: Option<ReviewSummaryRecord>,
    pub stage_timeline: Vec<WorkflowStageSummary>,
    pub artifacts: Vec<JobArtifactRecord>,
    pub commands: Vec<JobCommandRecord>,
    pub is_command_running: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct CreatePrinterInput {
    pub manufacturer: String,
    pub model: String,
    pub nickname: String,
    pub transport_style: String,
    pub colorant_family: ColorantFamily,
    pub channel_count: u32,
    pub channel_labels: Vec<String>,
    pub supported_media_settings: Vec<String>,
    pub supported_quality_modes: Vec<String>,
    pub monochrome_path_notes: String,
    pub notes: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct UpdatePrinterInput {
    pub id: String,
    pub manufacturer: String,
    pub model: String,
    pub nickname: String,
    pub transport_style: String,
    pub colorant_family: ColorantFamily,
    pub channel_count: u32,
    pub channel_labels: Vec<String>,
    pub supported_media_settings: Vec<String>,
    pub supported_quality_modes: Vec<String>,
    pub monochrome_path_notes: String,
    pub notes: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct CreatePaperInput {
    pub manufacturer: String,
    pub paper_line: String,
    pub surface_class: String,
    pub basis_weight_value: String,
    pub basis_weight_unit: PaperWeightUnit,
    pub thickness_value: String,
    pub thickness_unit: PaperThicknessUnit,
    pub surface_texture: String,
    pub base_material: String,
    pub media_color: String,
    pub opacity: String,
    pub whiteness: String,
    pub oba_content: String,
    pub ink_compatibility: String,
    pub notes: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct UpdatePaperInput {
    pub id: String,
    pub manufacturer: String,
    pub paper_line: String,
    pub surface_class: String,
    pub basis_weight_value: String,
    pub basis_weight_unit: PaperWeightUnit,
    pub thickness_value: String,
    pub thickness_unit: PaperThicknessUnit,
    pub surface_texture: String,
    pub base_material: String,
    pub media_color: String,
    pub opacity: String,
    pub whiteness: String,
    pub oba_content: String,
    pub ink_compatibility: String,
    pub notes: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct CreatePrinterPaperPresetInput {
    pub printer_id: String,
    pub paper_id: String,
    pub label: String,
    pub print_path: String,
    pub media_setting: String,
    pub quality_mode: String,
    pub total_ink_limit_percent: Option<u32>,
    pub black_ink_limit_percent: Option<u32>,
    pub notes: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct UpdatePrinterPaperPresetInput {
    pub id: String,
    pub printer_id: String,
    pub paper_id: String,
    pub label: String,
    pub print_path: String,
    pub media_setting: String,
    pub quality_mode: String,
    pub total_ink_limit_percent: Option<u32>,
    pub black_ink_limit_percent: Option<u32>,
    pub notes: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct CreateNewProfileDraftInput {
    pub profile_name: Option<String>,
    pub printer_id: Option<String>,
    pub paper_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct SaveNewProfileContextInput {
    pub job_id: String,
    pub profile_name: String,
    pub printer_id: Option<String>,
    pub paper_id: Option<String>,
    pub printer_paper_preset_id: Option<String>,
    pub print_path: String,
    pub media_setting: String,
    pub quality_mode: String,
    pub print_path_notes: String,
    pub measurement_notes: String,
    pub measurement_observer: String,
    pub measurement_illuminant: String,
    pub measurement_mode: MeasurementMode,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct SaveTargetSettingsInput {
    pub job_id: String,
    pub patch_count: u32,
    pub improve_neutrals: bool,
    pub use_existing_profile_to_help_target_planning: bool,
    pub planning_profile_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct SavePrintSettingsInput {
    pub job_id: String,
    pub print_without_color_management: bool,
    pub drying_time_minutes: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct StartMeasurementInput {
    pub job_id: String,
    pub scan_file_path: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub(crate) struct EngineState {
    pub config: Option<EngineConfig>,
    pub bootstrap_status: Option<BootstrapStatus>,
    pub app_health: AppHealth,
    pub toolchain_status: ToolchainStatus,
    pub dashboard_snapshot: DashboardSnapshot,
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
            argyll_version: None,
            last_validation_time: None,
        }
    }
}

impl Default for InstrumentStatus {
    fn default() -> Self {
        Self {
            state: InstrumentConnectionState::Disconnected,
            label: "No Instrument Connected".to_string(),
            detail: None,
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
