use crate::model::{
    ActiveWorkItem, ArtifactKind, CommandRunState, CommandStream, CreateNewProfileDraftInput,
    CreatePaperInput, CreatePrinterInput, DashboardSnapshot, DeleteJobResult, EngineConfig,
    InstrumentStatus, JobArtifactRecord, JobCommandEventRecord, JobCommandRecord, MeasurementMode,
    MeasurementStatusRecord, NewProfileContextRecord, NewProfileJobDetail, PaperRecord,
    PrintSettingsRecord, PrinterProfileRecord, PrinterRecord, ReviewSummaryRecord,
    SaveNewProfileContextInput, SavePrintSettingsInput, SaveTargetSettingsInput,
    StartMeasurementInput, TargetSettingsRecord, ToolchainState, ToolchainStatus, UpdatePaperInput,
    UpdatePrinterInput, WorkflowStage, WorkflowStageState, WorkflowStageSummary,
};
use crate::support::{EngineResult, ensure_directory, iso_timestamp};
use chrono::{Duration, Utc};
use rusqlite::{Connection, OptionalExtension, params};
use std::path::Path;

const TOOLCHAIN_OVERRIDE_KEY: &str = "toolchain.override_path";
const DATABASE_VERSION: i64 = 3;

pub struct DatabaseStatus {
    pub initialized: bool,
    pub migrations_applied: bool,
    pub persisted_override_path: Option<String>,
}

#[derive(Debug, Clone)]
pub(crate) struct NewProfileRunnerContext {
    pub job_id: String,
    pub title: String,
    pub profile_name: String,
    pub printer_name: String,
    pub paper_name: String,
    pub workspace_path: String,
    pub media_setting: String,
    pub quality_mode: String,
    pub measurement_observer: String,
    pub measurement_mode: MeasurementMode,
    pub patch_count: u32,
    pub improve_neutrals: bool,
    pub planning_profile_path: Option<String>,
    pub measurement_source_path: Option<String>,
    pub scan_file_path: Option<String>,
    pub has_measurement_checkpoint: bool,
}

pub fn initialize_database(config: &EngineConfig) -> EngineResult<DatabaseStatus> {
    let database_exists = Path::new(&config.database_path).exists();
    let connection = open_connection(&config.database_path)?;
    let migrations_applied = apply_migrations(&connection, &config.app_support_path)?;
    let persisted_override_path = load_setting(&connection, TOOLCHAIN_OVERRIDE_KEY)?;

    Ok(DatabaseStatus {
        initialized: database_exists || Path::new(&config.database_path).exists(),
        migrations_applied,
        persisted_override_path,
    })
}

pub fn persist_toolchain_override(database_path: &str, value: Option<&str>) -> EngineResult<()> {
    let connection = open_connection(database_path)?;

    match value {
        Some(path) => {
            connection.execute(
                r#"
                INSERT INTO app_settings (key, value, updated_at)
                VALUES (?1, ?2, ?3)
                ON CONFLICT(key) DO UPDATE SET
                    value = excluded.value,
                    updated_at = excluded.updated_at
                "#,
                params![TOOLCHAIN_OVERRIDE_KEY, path, iso_timestamp()],
            )?;
        }
        None => {
            connection.execute(
                "DELETE FROM app_settings WHERE key = ?1",
                params![TOOLCHAIN_OVERRIDE_KEY],
            )?;
        }
    }

    Ok(())
}

pub fn persist_toolchain_status(database_path: &str, status: &ToolchainStatus) -> EngineResult<()> {
    let connection = open_connection(database_path)?;
    connection.execute(
        r#"
        INSERT INTO toolchain_status_cache (
            id,
            state,
            resolved_install_path,
            discovered_executables,
            missing_executables,
            argyll_version,
            last_validation_time
        )
        VALUES (1, ?1, ?2, ?3, ?4, ?5, ?6)
        ON CONFLICT(id) DO UPDATE SET
            state = excluded.state,
            resolved_install_path = excluded.resolved_install_path,
            discovered_executables = excluded.discovered_executables,
            missing_executables = excluded.missing_executables,
            argyll_version = excluded.argyll_version,
            last_validation_time = excluded.last_validation_time
        "#,
        params![
            encode_toolchain_state(&status.state),
            status.resolved_install_path,
            encode_json(&status.discovered_executables)?,
            encode_json(&status.missing_executables)?,
            status.argyll_version,
            status.last_validation_time
        ],
    )?;
    Ok(())
}

pub fn load_dashboard_snapshot(database_path: &str) -> EngineResult<DashboardSnapshot> {
    let connection = open_connection(database_path)?;
    let active_work_items = load_active_work_items_from_connection(&connection)?;

    Ok(DashboardSnapshot {
        jobs_count: active_work_items.len() as u32,
        active_work_items,
        alerts_count: 0,
        instrument_status: InstrumentStatus::default(),
    })
}

pub fn list_printers(database_path: &str) -> EngineResult<Vec<PrinterRecord>> {
    let connection = open_connection(database_path)?;
    load_printers(&connection)
}

pub fn create_printer(
    database_path: &str,
    input: &CreatePrinterInput,
) -> EngineResult<PrinterRecord> {
    let connection = open_connection(database_path)?;
    let id = format!("printer-{}", job_timestamp_seed());
    let now = iso_timestamp();
    let display_name = display_printer_name(&input.make_model, &input.nickname);

    connection.execute(
        r#"
        INSERT INTO printers (
            id,
            make_model,
            nickname,
            transport_style,
            supported_quality_modes,
            monochrome_path_notes,
            notes,
            created_at,
            updated_at
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
        "#,
        params![
            &id,
            trim(&input.make_model),
            trim(&input.nickname),
            trim(&input.transport_style),
            encode_json(&trimmed_strings(input.supported_quality_modes.clone()))?,
            trim(&input.monochrome_path_notes),
            trim(&input.notes),
            &now,
            &now
        ],
    )?;

    Ok(PrinterRecord {
        id,
        make_model: trim(&input.make_model),
        nickname: trim(&input.nickname),
        transport_style: trim(&input.transport_style),
        supported_quality_modes: trimmed_strings(input.supported_quality_modes.clone()),
        monochrome_path_notes: trim(&input.monochrome_path_notes),
        notes: trim(&input.notes),
        display_name,
        created_at: now.clone(),
        updated_at: now,
    })
}

pub fn update_printer(
    database_path: &str,
    input: &UpdatePrinterInput,
) -> EngineResult<PrinterRecord> {
    let connection = open_connection(database_path)?;
    let now = iso_timestamp();

    connection.execute(
        r#"
        UPDATE printers
        SET
            make_model = ?2,
            nickname = ?3,
            transport_style = ?4,
            supported_quality_modes = ?5,
            monochrome_path_notes = ?6,
            notes = ?7,
            updated_at = ?8
        WHERE id = ?1
        "#,
        params![
            &input.id,
            trim(&input.make_model),
            trim(&input.nickname),
            trim(&input.transport_style),
            encode_json(&trimmed_strings(input.supported_quality_modes.clone()))?,
            trim(&input.monochrome_path_notes),
            trim(&input.notes),
            &now
        ],
    )?;

    load_printer(&connection, &input.id)?.ok_or_else(|| "printer not found".into())
}

pub fn list_papers(database_path: &str) -> EngineResult<Vec<PaperRecord>> {
    let connection = open_connection(database_path)?;
    load_papers(&connection)
}

pub fn create_paper(database_path: &str, input: &CreatePaperInput) -> EngineResult<PaperRecord> {
    let connection = open_connection(database_path)?;
    let id = format!("paper-{}", job_timestamp_seed());
    let now = iso_timestamp();
    let display_name = display_paper_name(&input.vendor_product_name, &input.surface_class);

    connection.execute(
        r#"
        INSERT INTO papers (
            id,
            vendor_product_name,
            surface_class,
            weight_thickness,
            oba_fluorescence_notes,
            notes,
            created_at,
            updated_at
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
        "#,
        params![
            &id,
            trim(&input.vendor_product_name),
            trim(&input.surface_class),
            trim(&input.weight_thickness),
            trim(&input.oba_fluorescence_notes),
            trim(&input.notes),
            &now,
            &now
        ],
    )?;

    Ok(PaperRecord {
        id,
        vendor_product_name: trim(&input.vendor_product_name),
        surface_class: trim(&input.surface_class),
        weight_thickness: trim(&input.weight_thickness),
        oba_fluorescence_notes: trim(&input.oba_fluorescence_notes),
        notes: trim(&input.notes),
        display_name,
        created_at: now.clone(),
        updated_at: now,
    })
}

pub fn update_paper(database_path: &str, input: &UpdatePaperInput) -> EngineResult<PaperRecord> {
    let connection = open_connection(database_path)?;
    let now = iso_timestamp();

    connection.execute(
        r#"
        UPDATE papers
        SET
            vendor_product_name = ?2,
            surface_class = ?3,
            weight_thickness = ?4,
            oba_fluorescence_notes = ?5,
            notes = ?6,
            updated_at = ?7
        WHERE id = ?1
        "#,
        params![
            &input.id,
            trim(&input.vendor_product_name),
            trim(&input.surface_class),
            trim(&input.weight_thickness),
            trim(&input.oba_fluorescence_notes),
            trim(&input.notes),
            &now
        ],
    )?;

    load_paper(&connection, &input.id)?.ok_or_else(|| "paper not found".into())
}

pub fn list_printer_profiles(database_path: &str) -> EngineResult<Vec<PrinterProfileRecord>> {
    let connection = open_connection(database_path)?;
    load_printer_profiles(&connection)
}

pub fn create_new_profile_draft(
    database_path: &str,
    app_support_path: &str,
    input: &CreateNewProfileDraftInput,
) -> EngineResult<NewProfileJobDetail> {
    let connection = open_connection(database_path)?;
    let id = format!("job-{}", job_timestamp_seed());
    let now = iso_timestamp();
    let workspace_path = workspace_path(app_support_path, &id);
    ensure_directory(Path::new(&workspace_path))?;
    let profile_name = input.profile_name.as_deref().map(trim).unwrap_or_default();
    let title = if profile_name.is_empty() {
        "New Profile".to_string()
    } else {
        profile_name.clone()
    };
    let printer_name = input
        .printer_id
        .as_deref()
        .and_then(|printer_id| load_printer(&connection, printer_id).ok().flatten())
        .map(|printer| printer.display_name)
        .unwrap_or_default();
    let paper_name = input
        .paper_id
        .as_deref()
        .and_then(|paper_id| load_paper(&connection, paper_id).ok().flatten())
        .map(|paper| paper.display_name)
        .unwrap_or_default();

    connection.execute(
        r#"
        INSERT INTO jobs (
            id,
            name,
            kind,
            route,
            title,
            printer_name,
            paper_name,
            stage,
            next_action,
            status,
            created_at,
            updated_at
        )
        VALUES (?1, ?2, 'new_profile', 'home', ?3, ?4, ?5, 'context', ?6, 'draft', ?7, ?8)
        "#,
        params![
            &id,
            &profile_name,
            &title,
            &printer_name,
            &paper_name,
            "Select or create a printer and paper",
            &now,
            &now
        ],
    )?;

    connection.execute(
        r#"
        INSERT INTO new_profile_jobs (
            id,
            workspace_path,
            profile_name,
            printer_id,
            paper_id,
            media_setting,
            quality_mode,
            print_path_notes,
            measurement_notes,
            measurement_observer,
            measurement_illuminant,
            measurement_mode,
            patch_count,
            improve_neutrals,
            use_existing_profile_planning,
            planning_profile_id,
            print_without_color_management,
            drying_time_minutes,
            printed_at,
            drying_ready_at,
            measurement_source_path,
            scan_file_path,
            has_measurement_checkpoint,
            latest_error,
            published_profile_id,
            created_at,
            updated_at
        )
        VALUES (?1, ?2, ?3, ?4, ?5, '', '', '', '', '1931_2', 'D50', 'strip', 836, 0, 0, NULL, 1, 120, NULL, NULL, NULL, NULL, 0, NULL, NULL, ?6, ?7)
        "#,
        params![
            &id,
            &workspace_path,
            &profile_name,
            input.printer_id.as_deref(),
            input.paper_id.as_deref(),
            &now,
            &now
        ],
    )?;

    load_new_profile_job_detail_from_connection(&connection, &id)
}

pub fn load_new_profile_job_detail(
    database_path: &str,
    job_id: &str,
) -> EngineResult<NewProfileJobDetail> {
    let connection = open_connection(database_path)?;
    load_new_profile_job_detail_from_connection(&connection, job_id)
}

pub fn delete_new_profile_job(database_path: &str, job_id: &str) -> EngineResult<DeleteJobResult> {
    let connection = open_connection(database_path)?;
    let detail = load_new_profile_job_detail_from_connection(&connection, job_id)?;

    if detail.is_command_running {
        return Ok(DeleteJobResult {
            success: false,
            message: "Wait for the current Argyll command to finish before deleting this work."
                .to_string(),
        });
    }

    connection.execute(
        "DELETE FROM app_settings WHERE key = ?1",
        params![format!("new_profile.review.{job_id}")],
    )?;
    let deleted = connection.execute("DELETE FROM jobs WHERE id = ?1", params![job_id])?;

    if deleted == 0 {
        return Ok(DeleteJobResult {
            success: false,
            message: "Active work was not found.".to_string(),
        });
    }

    let workspace_path = Path::new(&detail.workspace_path);
    if workspace_path.exists() {
        let _ = std::fs::remove_dir_all(workspace_path);
    }

    Ok(DeleteJobResult {
        success: true,
        message: String::new(),
    })
}

pub fn save_new_profile_context(
    database_path: &str,
    input: &SaveNewProfileContextInput,
) -> EngineResult<NewProfileJobDetail> {
    let connection = open_connection(database_path)?;
    let now = iso_timestamp();
    let printer_name = input
        .printer_id
        .as_deref()
        .and_then(|printer_id| load_printer(&connection, printer_id).ok().flatten())
        .map(|printer| printer.display_name)
        .unwrap_or_default();
    let paper_name = input
        .paper_id
        .as_deref()
        .and_then(|paper_id| load_paper(&connection, paper_id).ok().flatten())
        .map(|paper| paper.display_name)
        .unwrap_or_default();
    let title = if trim(&input.profile_name).is_empty() {
        "New Profile".to_string()
    } else {
        trim(&input.profile_name)
    };

    connection.execute(
        r#"
        UPDATE new_profile_jobs
        SET
            profile_name = ?2,
            printer_id = ?3,
            paper_id = ?4,
            media_setting = ?5,
            quality_mode = ?6,
            print_path_notes = ?7,
            measurement_notes = ?8,
            measurement_observer = ?9,
            measurement_illuminant = ?10,
            measurement_mode = ?11,
            latest_error = NULL,
            updated_at = ?12
        WHERE id = ?1
        "#,
        params![
            &input.job_id,
            trim(&input.profile_name),
            input.printer_id.as_deref(),
            input.paper_id.as_deref(),
            trim(&input.media_setting),
            trim(&input.quality_mode),
            trim(&input.print_path_notes),
            trim(&input.measurement_notes),
            trim(&input.measurement_observer),
            trim(&input.measurement_illuminant),
            encode_measurement_mode(&input.measurement_mode),
            &now
        ],
    )?;

    let mut detail = load_new_profile_job_detail_from_connection(&connection, &input.job_id)?;
    sync_context_summary(
        &connection,
        &input.job_id,
        &title,
        &trim(&input.profile_name),
        &printer_name,
        &paper_name,
        &mut detail,
    )?;
    Ok(detail)
}

pub fn save_target_settings(
    database_path: &str,
    input: &SaveTargetSettingsInput,
) -> EngineResult<NewProfileJobDetail> {
    let connection = open_connection(database_path)?;
    let now = iso_timestamp();

    connection.execute(
        r#"
        UPDATE new_profile_jobs
        SET
            patch_count = ?2,
            improve_neutrals = ?3,
            use_existing_profile_planning = ?4,
            planning_profile_id = ?5,
            latest_error = NULL,
            updated_at = ?6
        WHERE id = ?1
        "#,
        params![
            &input.job_id,
            input.patch_count.max(64),
            encode_bool(input.improve_neutrals),
            encode_bool(input.use_existing_profile_to_help_target_planning),
            input.planning_profile_id.as_deref(),
            &now
        ],
    )?;

    load_new_profile_job_detail_from_connection(&connection, &input.job_id)
}

pub fn save_print_settings(
    database_path: &str,
    input: &SavePrintSettingsInput,
) -> EngineResult<NewProfileJobDetail> {
    let connection = open_connection(database_path)?;
    let now = iso_timestamp();

    connection.execute(
        r#"
        UPDATE new_profile_jobs
        SET
            print_without_color_management = ?2,
            drying_time_minutes = ?3,
            latest_error = NULL,
            updated_at = ?4
        WHERE id = ?1
        "#,
        params![
            &input.job_id,
            encode_bool(input.print_without_color_management),
            input.drying_time_minutes.max(1),
            &now
        ],
    )?;

    load_new_profile_job_detail_from_connection(&connection, &input.job_id)
}

pub fn prepare_generate_target(
    database_path: &str,
    job_id: &str,
) -> EngineResult<NewProfileJobDetail> {
    let connection = open_connection(database_path)?;
    let detail = load_new_profile_job_detail_from_connection(&connection, job_id)?;
    ensure_action_allowed(
        &detail,
        &[WorkflowStage::Context, WorkflowStage::Target],
        false,
    )?;
    ensure_context_complete(&detail)?;
    update_job_summary(
        &connection,
        job_id,
        WorkflowStage::Target,
        "active",
        "Generating target files",
        &detail.profile_name,
        &detail.printer_name,
        &detail.paper_name,
    )?;
    clear_job_error(&connection, job_id)?;
    load_new_profile_job_detail_from_connection(&connection, job_id)
}

pub fn mark_new_profile_printed(
    database_path: &str,
    job_id: &str,
) -> EngineResult<NewProfileJobDetail> {
    let connection = open_connection(database_path)?;
    let detail = load_new_profile_job_detail_from_connection(&connection, job_id)?;
    ensure_action_allowed(&detail, &[WorkflowStage::Print], false)?;
    let printed_at = iso_timestamp();
    let drying_ready_at = (Utc::now()
        + Duration::minutes(detail.print_settings.drying_time_minutes as i64))
    .to_rfc3339();

    connection.execute(
        r#"
        UPDATE new_profile_jobs
        SET
            printed_at = ?2,
            drying_ready_at = ?3,
            latest_error = NULL,
            updated_at = ?4
        WHERE id = ?1
        "#,
        params![job_id, &printed_at, &drying_ready_at, iso_timestamp()],
    )?;

    update_job_summary(
        &connection,
        job_id,
        WorkflowStage::Drying,
        "active",
        "Wait for the drying timer or mark the target ready to measure",
        &detail.profile_name,
        &detail.printer_name,
        &detail.paper_name,
    )?;

    load_new_profile_job_detail_from_connection(&connection, job_id)
}

pub fn mark_new_profile_ready_to_measure(
    database_path: &str,
    job_id: &str,
) -> EngineResult<NewProfileJobDetail> {
    let connection = open_connection(database_path)?;
    let detail = load_new_profile_job_detail_from_connection(&connection, job_id)?;
    ensure_action_allowed(&detail, &[WorkflowStage::Drying], false)?;

    update_job_summary(
        &connection,
        job_id,
        WorkflowStage::Measure,
        "ready",
        "Measure target",
        &detail.profile_name,
        &detail.printer_name,
        &detail.paper_name,
    )?;

    load_new_profile_job_detail_from_connection(&connection, job_id)
}

pub fn prepare_measurement(
    database_path: &str,
    input: &StartMeasurementInput,
) -> EngineResult<NewProfileJobDetail> {
    let connection = open_connection(database_path)?;
    let detail = load_new_profile_job_detail_from_connection(&connection, &input.job_id)?;
    ensure_action_allowed(&detail, &[WorkflowStage::Measure], false)?;

    if detail.context.measurement_mode == MeasurementMode::ScanFile
        && input
            .scan_file_path
            .as_deref()
            .map(trim)
            .unwrap_or_default()
            .is_empty()
    {
        return Err("Scan File mode requires a scan file path.".into());
    }

    connection.execute(
        r#"
        UPDATE new_profile_jobs
        SET
            scan_file_path = COALESCE(?2, scan_file_path),
            latest_error = NULL,
            updated_at = ?3
        WHERE id = ?1
        "#,
        params![
            &input.job_id,
            input.scan_file_path.as_deref(),
            iso_timestamp()
        ],
    )?;

    update_job_summary(
        &connection,
        &input.job_id,
        WorkflowStage::Measure,
        "active",
        "Measuring target",
        &detail.profile_name,
        &detail.printer_name,
        &detail.paper_name,
    )?;

    load_new_profile_job_detail_from_connection(&connection, &input.job_id)
}

pub fn prepare_build_profile(
    database_path: &str,
    job_id: &str,
) -> EngineResult<NewProfileJobDetail> {
    let connection = open_connection(database_path)?;
    let detail = load_new_profile_job_detail_from_connection(&connection, job_id)?;
    ensure_action_allowed(&detail, &[WorkflowStage::Build], false)?;

    if detail.measurement.measurement_source_path.is_none() {
        return Err("Measure the target before building the profile.".into());
    }

    update_job_summary(
        &connection,
        job_id,
        WorkflowStage::Build,
        "active",
        "Building profile",
        &detail.profile_name,
        &detail.printer_name,
        &detail.paper_name,
    )?;
    clear_job_error(&connection, job_id)?;

    load_new_profile_job_detail_from_connection(&connection, job_id)
}

pub fn publish_new_profile(database_path: &str, job_id: &str) -> EngineResult<NewProfileJobDetail> {
    let connection = open_connection(database_path)?;
    let detail = load_new_profile_job_detail_from_connection(&connection, job_id)?;
    ensure_action_allowed(&detail, &[WorkflowStage::Review], false)?;

    let icc_artifact = detail
        .artifacts
        .iter()
        .find(|artifact| artifact.kind == ArtifactKind::IccProfile)
        .and_then(|artifact| artifact.path.clone())
        .ok_or("Build the profile before publishing it.")?;
    let measurement_path = detail
        .measurement
        .measurement_source_path
        .clone()
        .ok_or("No measurements are linked to this job.")?;
    let review = detail
        .review
        .clone()
        .ok_or("Review data is missing. Build the profile again.")?;
    let profile_id = format!("profile-{}", job_timestamp_seed());
    let now = iso_timestamp();
    let context_status = if detail.printer.is_some() && detail.paper.is_some() {
        "Known Context".to_string()
    } else {
        "Printer & Paper Settings Unknown".to_string()
    };

    connection.execute(
        r#"
        INSERT INTO printer_profiles (
            id,
            name,
            printer_name,
            paper_name,
            context_status,
            profile_path,
            measurement_path,
            print_settings,
            verified_against_file,
            result,
            last_verification_date,
            created_from_job_id,
            created_at,
            updated_at
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
        "#,
        params![
            &profile_id,
            &detail.profile_name,
            &detail.printer_name,
            &detail.paper_name,
            &context_status,
            &icc_artifact,
            &measurement_path,
            &review.print_settings,
            &review.verified_against_file,
            &review.result,
            review.last_verification_date.as_deref(),
            job_id,
            &now,
            &now
        ],
    )?;

    connection.execute(
        r#"
        UPDATE new_profile_jobs
        SET
            published_profile_id = ?2,
            updated_at = ?3
        WHERE id = ?1
        "#,
        params![job_id, &profile_id, &now],
    )?;

    update_job_summary(
        &connection,
        job_id,
        WorkflowStage::Completed,
        "completed",
        "Profile published",
        &detail.profile_name,
        &detail.printer_name,
        &detail.paper_name,
    )?;

    load_new_profile_job_detail_from_connection(&connection, job_id)
}

pub(crate) fn load_new_profile_runner_context(
    database_path: &str,
    job_id: &str,
) -> EngineResult<NewProfileRunnerContext> {
    let connection = open_connection(database_path)?;
    let detail = load_new_profile_job_detail_from_connection(&connection, job_id)?;
    let planning_profile_path = detail
        .target_settings
        .planning_profile_id
        .as_deref()
        .and_then(|profile_id| {
            connection
                .query_row(
                    "SELECT profile_path FROM printer_profiles WHERE id = ?1",
                    params![profile_id],
                    |row| row.get(0),
                )
                .optional()
                .ok()
                .flatten()
        });

    Ok(NewProfileRunnerContext {
        job_id: detail.id,
        title: detail.title,
        profile_name: detail.profile_name,
        printer_name: detail.printer_name,
        paper_name: detail.paper_name,
        workspace_path: detail.workspace_path,
        media_setting: detail.context.media_setting,
        quality_mode: detail.context.quality_mode,
        measurement_observer: detail.context.measurement_observer,
        measurement_mode: detail.context.measurement_mode,
        patch_count: detail.target_settings.patch_count,
        improve_neutrals: detail.target_settings.improve_neutrals,
        planning_profile_path,
        measurement_source_path: detail.measurement.measurement_source_path,
        scan_file_path: detail.measurement.scan_file_path,
        has_measurement_checkpoint: detail.measurement.has_measurement_checkpoint,
    })
}

pub(crate) fn insert_job_command(
    database_path: &str,
    job_id: &str,
    stage: WorkflowStage,
    label: &str,
    argv: &[String],
) -> EngineResult<String> {
    let connection = open_connection(database_path)?;
    let id = format!("cmd-{}", job_timestamp_seed());
    connection.execute(
        r#"
        INSERT INTO job_commands (
            id,
            job_id,
            stage,
            label,
            argv,
            state,
            exit_code,
            started_at,
            finished_at
        )
        VALUES (?1, ?2, ?3, ?4, ?5, 'running', NULL, ?6, NULL)
        "#,
        params![
            &id,
            job_id,
            encode_workflow_stage(&stage),
            label,
            encode_json(argv)?,
            iso_timestamp()
        ],
    )?;
    Ok(id)
}

pub(crate) fn append_job_command_event(
    database_path: &str,
    command_id: &str,
    stream: CommandStream,
    line_number: u32,
    message: &str,
) -> EngineResult<()> {
    let connection = open_connection(database_path)?;
    let event_id = format!(
        "event-{}-{}-{}",
        command_id,
        encode_command_stream(&stream),
        line_number
    );
    connection.execute(
        r#"
        INSERT INTO job_command_events (
            id,
            command_id,
            stream,
            line_number,
            message,
            timestamp
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6)
        "#,
        params![
            &event_id,
            command_id,
            encode_command_stream(&stream),
            line_number,
            message,
            iso_timestamp()
        ],
    )?;
    Ok(())
}

pub(crate) fn finish_job_command(
    database_path: &str,
    command_id: &str,
    succeeded: bool,
    exit_code: Option<i32>,
) -> EngineResult<()> {
    let connection = open_connection(database_path)?;
    connection.execute(
        r#"
        UPDATE job_commands
        SET
            state = ?2,
            exit_code = ?3,
            finished_at = ?4
        WHERE id = ?1
        "#,
        params![
            command_id,
            if succeeded { "succeeded" } else { "failed" },
            exit_code,
            iso_timestamp()
        ],
    )?;
    Ok(())
}

pub(crate) fn upsert_job_artifact(
    database_path: &str,
    job_id: &str,
    stage: WorkflowStage,
    kind: ArtifactKind,
    label: &str,
    path: Option<&str>,
    status: &str,
) -> EngineResult<()> {
    let connection = open_connection(database_path)?;
    let artifact_id = format!(
        "artifact-{}-{}",
        job_id,
        label.replace(' ', "-").to_lowercase()
    );
    let now = iso_timestamp();
    connection.execute(
        r#"
        INSERT INTO artifacts (
            id,
            job_id,
            name,
            label,
            kind,
            stage,
            status,
            path,
            created_at,
            updated_at
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            label = excluded.label,
            kind = excluded.kind,
            stage = excluded.stage,
            status = excluded.status,
            path = excluded.path,
            updated_at = excluded.updated_at
        "#,
        params![
            &artifact_id,
            job_id,
            label,
            label,
            encode_artifact_kind(&kind),
            encode_workflow_stage(&stage),
            status,
            path,
            &now,
            &now
        ],
    )?;
    Ok(())
}

pub(crate) fn complete_generate_target(
    database_path: &str,
    job_id: &str,
    ti1_path: &str,
    ti2_path: &str,
    printable_chart_path: &str,
    chart_template_path: Option<&str>,
) -> EngineResult<()> {
    let connection = open_connection(database_path)?;
    let detail = load_new_profile_job_detail_from_connection(&connection, job_id)?;

    upsert_job_artifact(
        database_path,
        job_id,
        WorkflowStage::Target,
        ArtifactKind::Ti1,
        "Target values",
        Some(ti1_path),
        "ready",
    )?;
    upsert_job_artifact(
        database_path,
        job_id,
        WorkflowStage::Target,
        ArtifactKind::Ti2,
        "Target layout",
        Some(ti2_path),
        "ready",
    )?;
    upsert_job_artifact(
        database_path,
        job_id,
        WorkflowStage::Print,
        ArtifactKind::PrintableChart,
        "Printable target",
        Some(printable_chart_path),
        "ready",
    )?;

    if let Some(chart_template_path) = chart_template_path {
        upsert_job_artifact(
            database_path,
            job_id,
            WorkflowStage::Measure,
            ArtifactKind::ChartTemplate,
            "Chart template",
            Some(chart_template_path),
            "ready",
        )?;
    }

    update_job_summary(
        &connection,
        job_id,
        WorkflowStage::Print,
        "ready",
        "Print the target without color management",
        &detail.profile_name,
        &detail.printer_name,
        &detail.paper_name,
    )?;
    clear_job_error(&connection, job_id)?;
    Ok(())
}

pub(crate) fn complete_measurement(
    database_path: &str,
    job_id: &str,
    measurement_path: &str,
    has_checkpoint: bool,
) -> EngineResult<()> {
    let connection = open_connection(database_path)?;
    let detail = load_new_profile_job_detail_from_connection(&connection, job_id)?;

    connection.execute(
        r#"
        UPDATE new_profile_jobs
        SET
            measurement_source_path = ?2,
            has_measurement_checkpoint = ?3,
            latest_error = NULL,
            updated_at = ?4
        WHERE id = ?1
        "#,
        params![
            job_id,
            measurement_path,
            encode_bool(has_checkpoint),
            iso_timestamp()
        ],
    )?;

    upsert_job_artifact(
        database_path,
        job_id,
        WorkflowStage::Measure,
        ArtifactKind::Measurement,
        "Measurements",
        Some(measurement_path),
        "ready",
    )?;

    update_job_summary(
        &connection,
        job_id,
        WorkflowStage::Build,
        "ready",
        "Build profile",
        &detail.profile_name,
        &detail.printer_name,
        &detail.paper_name,
    )?;
    Ok(())
}

pub(crate) fn complete_build_profile(
    database_path: &str,
    job_id: &str,
    profile_path: &str,
    verification_summary: &ReviewSummaryRecord,
) -> EngineResult<()> {
    let connection = open_connection(database_path)?;
    let detail = load_new_profile_job_detail_from_connection(&connection, job_id)?;
    let notes = if verification_summary.notes.is_empty() {
        None
    } else {
        Some(verification_summary.notes.as_str())
    };

    upsert_job_artifact(
        database_path,
        job_id,
        WorkflowStage::Build,
        ArtifactKind::IccProfile,
        "ICC profile",
        Some(profile_path),
        "ready",
    )?;
    upsert_job_artifact(
        database_path,
        job_id,
        WorkflowStage::Review,
        ArtifactKind::Verification,
        "Verification summary",
        detail.measurement.measurement_source_path.as_deref(),
        "ready",
    )?;

    connection.execute(
        r#"
        UPDATE new_profile_jobs
        SET
            latest_error = NULL,
            updated_at = ?2
        WHERE id = ?1
        "#,
        params![job_id, iso_timestamp()],
    )?;

    connection.execute(
        r#"
        INSERT INTO app_settings (key, value, updated_at)
        VALUES (?1, ?2, ?3)
        ON CONFLICT(key) DO UPDATE SET
            value = excluded.value,
            updated_at = excluded.updated_at
        "#,
        params![
            format!("new_profile.review.{}", job_id),
            serde_json::to_string(verification_summary)?,
            iso_timestamp()
        ],
    )?;

    if let Some(notes) = notes {
        connection.execute(
            r#"
            INSERT INTO app_settings (key, value, updated_at)
            VALUES (?1, ?2, ?3)
            ON CONFLICT(key) DO UPDATE SET
                value = excluded.value,
                updated_at = excluded.updated_at
            "#,
            params![
                format!("new_profile.review_notes.{}", job_id),
                notes,
                iso_timestamp()
            ],
        )?;
    }

    update_job_summary(
        &connection,
        job_id,
        WorkflowStage::Review,
        "ready",
        "Publish the profile or return later",
        &detail.profile_name,
        &detail.printer_name,
        &detail.paper_name,
    )?;
    Ok(())
}

pub(crate) fn mark_job_failed(
    database_path: &str,
    job_id: &str,
    stage: WorkflowStage,
    error_message: &str,
) -> EngineResult<()> {
    let connection = open_connection(database_path)?;
    let detail = load_new_profile_job_detail_from_connection(&connection, job_id)?;
    connection.execute(
        r#"
        UPDATE new_profile_jobs
        SET
            latest_error = ?2,
            updated_at = ?3
        WHERE id = ?1
        "#,
        params![job_id, error_message, iso_timestamp()],
    )?;

    update_job_summary(
        &connection,
        job_id,
        match stage {
            WorkflowStage::Build => WorkflowStage::Failed,
            WorkflowStage::Measure => WorkflowStage::Failed,
            WorkflowStage::Target => WorkflowStage::Failed,
            _ => WorkflowStage::Failed,
        },
        "failed",
        "Review the technical details",
        &detail.profile_name,
        &detail.printer_name,
        &detail.paper_name,
    )?;
    Ok(())
}

fn load_new_profile_job_detail_from_connection(
    connection: &Connection,
    job_id: &str,
) -> EngineResult<NewProfileJobDetail> {
    let row = connection
        .query_row(
            r#"
            SELECT
                jobs.id,
                jobs.title,
                jobs.status,
                jobs.stage,
                jobs.next_action,
                new_profile_jobs.profile_name,
                jobs.printer_name,
                jobs.paper_name,
                new_profile_jobs.workspace_path,
                new_profile_jobs.printer_id,
                new_profile_jobs.paper_id,
                new_profile_jobs.media_setting,
                new_profile_jobs.quality_mode,
                new_profile_jobs.print_path_notes,
                new_profile_jobs.measurement_notes,
                new_profile_jobs.measurement_observer,
                new_profile_jobs.measurement_illuminant,
                new_profile_jobs.measurement_mode,
                new_profile_jobs.patch_count,
                new_profile_jobs.improve_neutrals,
                new_profile_jobs.use_existing_profile_planning,
                new_profile_jobs.planning_profile_id,
                new_profile_jobs.print_without_color_management,
                new_profile_jobs.drying_time_minutes,
                new_profile_jobs.printed_at,
                new_profile_jobs.drying_ready_at,
                new_profile_jobs.measurement_source_path,
                new_profile_jobs.scan_file_path,
                new_profile_jobs.has_measurement_checkpoint,
                new_profile_jobs.latest_error,
                new_profile_jobs.published_profile_id
            FROM jobs
            INNER JOIN new_profile_jobs ON new_profile_jobs.id = jobs.id
            WHERE jobs.id = ?1
            "#,
            params![job_id],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, String>(4)?,
                    row.get::<_, String>(5)?,
                    row.get::<_, String>(6)?,
                    row.get::<_, String>(7)?,
                    row.get::<_, String>(8)?,
                    row.get::<_, Option<String>>(9)?,
                    row.get::<_, Option<String>>(10)?,
                    row.get::<_, String>(11)?,
                    row.get::<_, String>(12)?,
                    row.get::<_, String>(13)?,
                    row.get::<_, String>(14)?,
                    row.get::<_, String>(15)?,
                    row.get::<_, String>(16)?,
                    row.get::<_, String>(17)?,
                    row.get::<_, i64>(18)?,
                    row.get::<_, i64>(19)?,
                    row.get::<_, i64>(20)?,
                    row.get::<_, Option<String>>(21)?,
                    row.get::<_, i64>(22)?,
                    row.get::<_, i64>(23)?,
                    row.get::<_, Option<String>>(24)?,
                    row.get::<_, Option<String>>(25)?,
                    row.get::<_, Option<String>>(26)?,
                    row.get::<_, Option<String>>(27)?,
                    row.get::<_, i64>(28)?,
                    row.get::<_, Option<String>>(29)?,
                    row.get::<_, Option<String>>(30)?,
                ))
            },
        )
        .optional()?
        .ok_or_else(|| format!("New Profile job {job_id} was not found."))?;

    let printer = row
        .9
        .as_deref()
        .map(|printer_id| load_printer(connection, printer_id))
        .transpose()?
        .flatten();
    let paper = row
        .10
        .as_deref()
        .map(|paper_id| load_paper(connection, paper_id))
        .transpose()?
        .flatten();
    let planning_profile_name = row
        .21
        .as_deref()
        .map(|profile_id| {
            connection
                .query_row(
                    "SELECT name FROM printer_profiles WHERE id = ?1",
                    params![profile_id],
                    |profile_row| profile_row.get(0),
                )
                .optional()
                .map_err(|error| -> Box<dyn std::error::Error + Send + Sync> { Box::new(error) })
        })
        .transpose()?
        .flatten();
    let review = load_review_summary(connection, &row.0)?;
    let commands = load_job_commands(connection, &row.0)?;
    let is_command_running = commands
        .iter()
        .any(|command| command.state == CommandRunState::Running);

    Ok(NewProfileJobDetail {
        id: row.0.clone(),
        title: row.1,
        status: row.2.clone(),
        stage: decode_workflow_stage(&row.3),
        next_action: row.4,
        profile_name: row.5,
        printer_name: row.6,
        paper_name: row.7,
        workspace_path: row.8,
        printer,
        paper,
        context: NewProfileContextRecord {
            media_setting: row.11,
            quality_mode: row.12,
            print_path_notes: row.13,
            measurement_notes: row.14,
            measurement_observer: row.15,
            measurement_illuminant: row.16,
            measurement_mode: decode_measurement_mode(&row.17),
        },
        target_settings: TargetSettingsRecord {
            patch_count: row.18.max(64) as u32,
            improve_neutrals: decode_bool(row.19),
            use_existing_profile_to_help_target_planning: decode_bool(row.20),
            planning_profile_id: row.21,
            planning_profile_name,
        },
        print_settings: PrintSettingsRecord {
            print_without_color_management: decode_bool(row.22),
            drying_time_minutes: row.23.max(1) as u32,
            printed_at: row.24,
            drying_ready_at: row.25,
        },
        measurement: MeasurementStatusRecord {
            measurement_source_path: row.26,
            scan_file_path: row.27,
            has_measurement_checkpoint: decode_bool(row.28),
        },
        latest_error: row.29,
        published_profile_id: row.30,
        review,
        stage_timeline: build_stage_timeline(&row.3),
        artifacts: load_job_artifacts(connection, &row.0)?,
        commands,
        is_command_running,
    })
}

fn load_active_work_items_from_connection(
    connection: &Connection,
) -> EngineResult<Vec<ActiveWorkItem>> {
    let mut statement = connection.prepare(
        r#"
        SELECT
            id,
            title,
            next_action,
            kind,
            stage,
            name,
            printer_name,
            paper_name,
            status
        FROM jobs
        WHERE status IN ('draft', 'ready', 'active', 'review', 'blocked', 'failed')
        ORDER BY updated_at DESC
        "#,
    )?;

    let rows = statement.query_map([], |row| {
        Ok(ActiveWorkItem {
            id: row.get(0)?,
            title: row.get(1)?,
            next_action: row.get(2)?,
            kind: row.get(3)?,
            stage: decode_workflow_stage(&row.get::<_, String>(4)?),
            profile_name: row.get(5)?,
            printer_name: row.get(6)?,
            paper_name: row.get(7)?,
            status: row.get(8)?,
        })
    })?;

    rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
}

fn load_printers(connection: &Connection) -> EngineResult<Vec<PrinterRecord>> {
    let mut statement = connection.prepare(
        r#"
        SELECT
            id,
            make_model,
            nickname,
            transport_style,
            supported_quality_modes,
            monochrome_path_notes,
            notes,
            created_at,
            updated_at
        FROM printers
        ORDER BY COALESCE(NULLIF(nickname, ''), make_model), updated_at DESC
        "#,
    )?;

    let rows = statement.query_map([], map_printer_row)?;
    rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
}

fn load_papers(connection: &Connection) -> EngineResult<Vec<PaperRecord>> {
    let mut statement = connection.prepare(
        r#"
        SELECT
            id,
            vendor_product_name,
            surface_class,
            weight_thickness,
            oba_fluorescence_notes,
            notes,
            created_at,
            updated_at
        FROM papers
        ORDER BY vendor_product_name, updated_at DESC
        "#,
    )?;

    let rows = statement.query_map([], map_paper_row)?;
    rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
}

fn load_printer(connection: &Connection, printer_id: &str) -> EngineResult<Option<PrinterRecord>> {
    connection
        .query_row(
            r#"
            SELECT
                id,
                make_model,
                nickname,
                transport_style,
                supported_quality_modes,
                monochrome_path_notes,
                notes,
                created_at,
                updated_at
            FROM printers
            WHERE id = ?1
            "#,
            params![printer_id],
            map_printer_row,
        )
        .optional()
        .map_err(Into::into)
}

fn load_paper(connection: &Connection, paper_id: &str) -> EngineResult<Option<PaperRecord>> {
    connection
        .query_row(
            r#"
            SELECT
                id,
                vendor_product_name,
                surface_class,
                weight_thickness,
                oba_fluorescence_notes,
                notes,
                created_at,
                updated_at
            FROM papers
            WHERE id = ?1
            "#,
            params![paper_id],
            map_paper_row,
        )
        .optional()
        .map_err(Into::into)
}

fn map_printer_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<PrinterRecord> {
    let make_model: String = row.get(1)?;
    let nickname: String = row.get(2)?;
    let quality_modes_json: String = row.get(4)?;
    let supported_quality_modes: Vec<String> =
        serde_json::from_str(&quality_modes_json).unwrap_or_default();

    Ok(PrinterRecord {
        id: row.get(0)?,
        make_model: make_model.clone(),
        nickname: nickname.clone(),
        transport_style: row.get(3)?,
        supported_quality_modes,
        monochrome_path_notes: row.get(5)?,
        notes: row.get(6)?,
        display_name: display_printer_name(&make_model, &nickname),
        created_at: row.get(7)?,
        updated_at: row.get(8)?,
    })
}

fn map_paper_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<PaperRecord> {
    let vendor_product_name: String = row.get(1)?;
    let surface_class: String = row.get(2)?;

    Ok(PaperRecord {
        id: row.get(0)?,
        vendor_product_name: vendor_product_name.clone(),
        surface_class: surface_class.clone(),
        weight_thickness: row.get(3)?,
        oba_fluorescence_notes: row.get(4)?,
        notes: row.get(5)?,
        display_name: display_paper_name(&vendor_product_name, &surface_class),
        created_at: row.get(6)?,
        updated_at: row.get(7)?,
    })
}

fn load_job_artifacts(
    connection: &Connection,
    job_id: &str,
) -> EngineResult<Vec<JobArtifactRecord>> {
    let mut statement = connection.prepare(
        r#"
        SELECT
            id,
            stage,
            kind,
            label,
            status,
            path,
            created_at,
            updated_at
        FROM artifacts
        WHERE job_id = ?1
        ORDER BY updated_at DESC, label
        "#,
    )?;

    let rows = statement.query_map(params![job_id], |row| {
        Ok(JobArtifactRecord {
            id: row.get(0)?,
            stage: decode_workflow_stage(&row.get::<_, String>(1)?),
            kind: decode_artifact_kind(&row.get::<_, String>(2)?),
            label: row.get(3)?,
            status: row.get(4)?,
            path: row.get(5)?,
            created_at: row.get(6)?,
            updated_at: row.get(7)?,
        })
    })?;

    rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
}

fn load_job_commands(connection: &Connection, job_id: &str) -> EngineResult<Vec<JobCommandRecord>> {
    let mut statement = connection.prepare(
        r#"
        SELECT
            id,
            stage,
            label,
            argv,
            state,
            exit_code,
            started_at,
            finished_at
        FROM job_commands
        WHERE job_id = ?1
        ORDER BY started_at DESC, id DESC
        "#,
    )?;

    let rows = statement.query_map(params![job_id], |row| {
        let command_id: String = row.get(0)?;
        let mut event_statement = connection.prepare(
            r#"
            SELECT
                id,
                command_id,
                stream,
                line_number,
                message,
                timestamp
            FROM job_command_events
            WHERE command_id = ?1
            ORDER BY line_number ASC, timestamp ASC
            "#,
        )?;
        let events = event_statement
            .query_map(params![&command_id], |event_row| {
                Ok(JobCommandEventRecord {
                    id: event_row.get(0)?,
                    command_id: event_row.get(1)?,
                    stream: decode_command_stream(&event_row.get::<_, String>(2)?),
                    line_number: event_row.get::<_, i64>(3)?.max(0) as u32,
                    message: event_row.get(4)?,
                    timestamp: event_row.get(5)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(JobCommandRecord {
            id: command_id,
            stage: decode_workflow_stage(&row.get::<_, String>(1)?),
            label: row.get(2)?,
            argv: decode_json::<Vec<String>>(&row.get::<_, String>(3)?),
            state: decode_command_run_state(&row.get::<_, String>(4)?),
            exit_code: row.get(5)?,
            started_at: row.get(6)?,
            finished_at: row.get(7)?,
            events,
        })
    })?;

    rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
}

fn load_printer_profiles(connection: &Connection) -> EngineResult<Vec<PrinterProfileRecord>> {
    let mut statement = connection.prepare(
        r#"
        SELECT
            id,
            name,
            printer_name,
            paper_name,
            context_status,
            profile_path,
            measurement_path,
            print_settings,
            verified_against_file,
            result,
            last_verification_date,
            created_from_job_id,
            created_at,
            updated_at
        FROM printer_profiles
        ORDER BY updated_at DESC, name
        "#,
    )?;

    let rows = statement.query_map([], |row| {
        Ok(PrinterProfileRecord {
            id: row.get(0)?,
            name: row.get(1)?,
            printer_name: row.get(2)?,
            paper_name: row.get(3)?,
            context_status: row.get(4)?,
            profile_path: row.get(5)?,
            measurement_path: row.get(6)?,
            print_settings: row.get(7)?,
            verified_against_file: row.get(8)?,
            result: row.get(9)?,
            last_verification_date: row.get(10)?,
            created_from_job_id: row.get(11)?,
            created_at: row.get(12)?,
            updated_at: row.get(13)?,
        })
    })?;

    rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
}

fn load_review_summary(
    connection: &Connection,
    job_id: &str,
) -> EngineResult<Option<ReviewSummaryRecord>> {
    let review_key = format!("new_profile.review.{job_id}");
    load_setting(connection, &review_key)?
        .map(|raw| serde_json::from_str::<ReviewSummaryRecord>(&raw).map_err(Into::into))
        .transpose()
}

fn sync_context_summary(
    connection: &Connection,
    job_id: &str,
    title: &str,
    profile_name: &str,
    printer_name: &str,
    paper_name: &str,
    detail: &mut NewProfileJobDetail,
) -> EngineResult<()> {
    let next_action =
        if profile_name.is_empty() || detail.printer.is_none() || detail.paper.is_none() {
            "Select or create a printer and paper"
        } else {
            "Generate target files"
        };
    let stage = if profile_name.is_empty() || detail.printer.is_none() || detail.paper.is_none() {
        WorkflowStage::Context
    } else if matches!(detail.stage, WorkflowStage::Context) {
        WorkflowStage::Target
    } else {
        detail.stage.clone()
    };
    let status = if matches!(stage, WorkflowStage::Context) {
        "draft"
    } else {
        "ready"
    };

    update_job_summary(
        connection,
        job_id,
        stage,
        status,
        next_action,
        profile_name,
        printer_name,
        paper_name,
    )?;
    detail.title = title.to_string();
    detail.profile_name = profile_name.to_string();
    detail.printer_name = printer_name.to_string();
    detail.paper_name = paper_name.to_string();
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn update_job_summary(
    connection: &Connection,
    job_id: &str,
    stage: WorkflowStage,
    status: &str,
    next_action: &str,
    profile_name: &str,
    printer_name: &str,
    paper_name: &str,
) -> EngineResult<()> {
    let title = if profile_name.is_empty() {
        "New Profile".to_string()
    } else {
        profile_name.to_string()
    };
    connection.execute(
        r#"
        UPDATE jobs
        SET
            name = ?2,
            title = ?3,
            printer_name = ?4,
            paper_name = ?5,
            stage = ?6,
            next_action = ?7,
            status = ?8,
            updated_at = ?9
        WHERE id = ?1
        "#,
        params![
            job_id,
            profile_name,
            &title,
            printer_name,
            paper_name,
            encode_workflow_stage(&stage),
            next_action,
            status,
            iso_timestamp()
        ],
    )?;
    Ok(())
}

fn clear_job_error(connection: &Connection, job_id: &str) -> EngineResult<()> {
    connection.execute(
        r#"
        UPDATE new_profile_jobs
        SET
            latest_error = NULL,
            updated_at = ?2
        WHERE id = ?1
        "#,
        params![job_id, iso_timestamp()],
    )?;
    Ok(())
}

fn ensure_action_allowed(
    detail: &NewProfileJobDetail,
    allowed_stages: &[WorkflowStage],
    allow_running: bool,
) -> EngineResult<()> {
    if !allowed_stages.contains(&detail.stage) {
        return Err(format!(
            "This action is not available while the job is in {:?}.",
            detail.stage
        )
        .into());
    }
    if detail.is_command_running && !allow_running {
        return Err("Wait for the current Argyll command to finish.".into());
    }
    Ok(())
}

fn ensure_context_complete(detail: &NewProfileJobDetail) -> EngineResult<()> {
    if detail.profile_name.trim().is_empty() {
        return Err("Enter a profile name before generating target files.".into());
    }
    if detail.printer.is_none() {
        return Err("Select or create a printer before generating target files.".into());
    }
    if detail.paper.is_none() {
        return Err("Select or create a paper before generating target files.".into());
    }
    Ok(())
}

fn workspace_path(app_support_path: &str, job_id: &str) -> String {
    Path::new(app_support_path)
        .join("jobs")
        .join(job_id)
        .to_string_lossy()
        .to_string()
}

fn open_connection(database_path: &str) -> EngineResult<Connection> {
    let connection = Connection::open(database_path)?;
    connection.pragma_update(None, "foreign_keys", "ON")?;
    connection.pragma_update(None, "journal_mode", "WAL")?;
    Ok(connection)
}

fn apply_migrations(connection: &Connection, app_support_path: &str) -> EngineResult<bool> {
    let current_version: i64 =
        connection.pragma_query_value(None, "user_version", |row| row.get(0))?;

    if current_version >= DATABASE_VERSION {
        return Ok(false);
    }

    connection.execute_batch("BEGIN;")?;
    create_latest_schema(connection)?;
    upgrade_legacy_jobs(connection, app_support_path)?;
    connection.pragma_update(None, "user_version", DATABASE_VERSION)?;
    connection.execute_batch("COMMIT;")?;
    Ok(true)
}

fn create_latest_schema(connection: &Connection) -> EngineResult<()> {
    connection.execute_batch(
        r#"
        CREATE TABLE IF NOT EXISTS app_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS toolchain_status_cache (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            state TEXT NOT NULL,
            resolved_install_path TEXT,
            discovered_executables TEXT NOT NULL,
            missing_executables TEXT NOT NULL,
            argyll_version TEXT,
            last_validation_time TEXT
        );

        CREATE TABLE IF NOT EXISTS print_configurations (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS jobs (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            kind TEXT NOT NULL DEFAULT 'new_profile',
            route TEXT NOT NULL DEFAULT 'home',
            title TEXT NOT NULL DEFAULT '',
            printer_name TEXT NOT NULL DEFAULT '',
            paper_name TEXT NOT NULL DEFAULT '',
            stage TEXT NOT NULL DEFAULT 'context',
            next_action TEXT NOT NULL DEFAULT 'Select or create a printer and paper',
            status TEXT NOT NULL DEFAULT 'draft',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS printers (
            id TEXT PRIMARY KEY,
            make_model TEXT NOT NULL,
            nickname TEXT NOT NULL DEFAULT '',
            transport_style TEXT NOT NULL DEFAULT '',
            supported_quality_modes TEXT NOT NULL DEFAULT '[]',
            monochrome_path_notes TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS papers (
            id TEXT PRIMARY KEY,
            vendor_product_name TEXT NOT NULL,
            surface_class TEXT NOT NULL DEFAULT '',
            weight_thickness TEXT NOT NULL DEFAULT '',
            oba_fluorescence_notes TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS new_profile_jobs (
            id TEXT PRIMARY KEY REFERENCES jobs(id) ON DELETE CASCADE,
            workspace_path TEXT NOT NULL,
            profile_name TEXT NOT NULL DEFAULT '',
            printer_id TEXT REFERENCES printers(id),
            paper_id TEXT REFERENCES papers(id),
            media_setting TEXT NOT NULL DEFAULT '',
            quality_mode TEXT NOT NULL DEFAULT '',
            print_path_notes TEXT NOT NULL DEFAULT '',
            measurement_notes TEXT NOT NULL DEFAULT '',
            measurement_observer TEXT NOT NULL DEFAULT '1931_2',
            measurement_illuminant TEXT NOT NULL DEFAULT 'D50',
            measurement_mode TEXT NOT NULL DEFAULT 'strip',
            patch_count INTEGER NOT NULL DEFAULT 836,
            improve_neutrals INTEGER NOT NULL DEFAULT 0,
            use_existing_profile_planning INTEGER NOT NULL DEFAULT 0,
            planning_profile_id TEXT REFERENCES printer_profiles(id),
            print_without_color_management INTEGER NOT NULL DEFAULT 1,
            drying_time_minutes INTEGER NOT NULL DEFAULT 120,
            printed_at TEXT,
            drying_ready_at TEXT,
            measurement_source_path TEXT,
            scan_file_path TEXT,
            has_measurement_checkpoint INTEGER NOT NULL DEFAULT 0,
            latest_error TEXT,
            published_profile_id TEXT REFERENCES printer_profiles(id),
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS artifacts (
            id TEXT PRIMARY KEY,
            job_id TEXT REFERENCES jobs(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            label TEXT NOT NULL DEFAULT '',
            kind TEXT NOT NULL DEFAULT 'working',
            stage TEXT NOT NULL DEFAULT 'context',
            status TEXT NOT NULL,
            path TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS job_commands (
            id TEXT PRIMARY KEY,
            job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
            stage TEXT NOT NULL,
            label TEXT NOT NULL,
            argv TEXT NOT NULL,
            state TEXT NOT NULL,
            exit_code INTEGER,
            started_at TEXT,
            finished_at TEXT
        );

        CREATE TABLE IF NOT EXISTS job_command_events (
            id TEXT PRIMARY KEY,
            command_id TEXT NOT NULL REFERENCES job_commands(id) ON DELETE CASCADE,
            stream TEXT NOT NULL,
            line_number INTEGER NOT NULL,
            message TEXT NOT NULL,
            timestamp TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS printer_profiles (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            printer_name TEXT NOT NULL,
            paper_name TEXT NOT NULL,
            context_status TEXT NOT NULL,
            profile_path TEXT NOT NULL,
            measurement_path TEXT NOT NULL,
            print_settings TEXT NOT NULL,
            verified_against_file TEXT NOT NULL,
            result TEXT NOT NULL,
            last_verification_date TEXT,
            created_from_job_id TEXT NOT NULL REFERENCES jobs(id),
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        "#,
    )?;

    ensure_column(
        connection,
        "toolchain_status_cache",
        "argyll_version",
        "TEXT",
    )?;
    ensure_column(
        connection,
        "jobs",
        "kind",
        "TEXT NOT NULL DEFAULT 'new_profile'",
    )?;
    ensure_column(connection, "jobs", "route", "TEXT NOT NULL DEFAULT 'home'")?;
    ensure_column(connection, "jobs", "title", "TEXT NOT NULL DEFAULT ''")?;
    ensure_column(
        connection,
        "jobs",
        "printer_name",
        "TEXT NOT NULL DEFAULT ''",
    )?;
    ensure_column(connection, "jobs", "paper_name", "TEXT NOT NULL DEFAULT ''")?;
    ensure_column(
        connection,
        "jobs",
        "stage",
        "TEXT NOT NULL DEFAULT 'context'",
    )?;
    ensure_column(
        connection,
        "jobs",
        "next_action",
        "TEXT NOT NULL DEFAULT 'Select or create a printer and paper'",
    )?;
    ensure_column(connection, "artifacts", "job_id", "TEXT")?;
    ensure_column(connection, "artifacts", "label", "TEXT NOT NULL DEFAULT ''")?;
    ensure_column(
        connection,
        "artifacts",
        "kind",
        "TEXT NOT NULL DEFAULT 'working'",
    )?;
    ensure_column(
        connection,
        "artifacts",
        "stage",
        "TEXT NOT NULL DEFAULT 'context'",
    )?;

    Ok(())
}

fn upgrade_legacy_jobs(connection: &Connection, app_support_path: &str) -> EngineResult<()> {
    connection.execute(
        r#"
        UPDATE jobs
        SET
            kind = COALESCE(NULLIF(kind, ''), 'new_profile'),
            route = COALESCE(NULLIF(route, ''), 'home'),
            title = COALESCE(NULLIF(title, ''), name),
            printer_name = COALESCE(printer_name, ''),
            paper_name = COALESCE(paper_name, ''),
            stage = COALESCE(NULLIF(stage, ''), 'context'),
            next_action = COALESCE(NULLIF(next_action, ''), 'Select or create a printer and paper'),
            status = CASE
                WHEN status IN ('setup', '') THEN 'draft'
                ELSE status
            END
        "#,
        [],
    )?;

    let mut statement = connection.prepare(
        r#"
        SELECT
            id,
            COALESCE(NULLIF(name, ''), ''),
            COALESCE(title, ''),
            COALESCE(printer_name, ''),
            COALESCE(paper_name, ''),
            COALESCE(created_at, ?1),
            COALESCE(updated_at, ?1)
        FROM jobs
        WHERE kind = 'new_profile'
        "#,
    )?;
    let now = iso_timestamp();
    let rows = statement.query_map(params![&now], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
            row.get::<_, String>(3)?,
            row.get::<_, String>(4)?,
            row.get::<_, String>(5)?,
            row.get::<_, String>(6)?,
        ))
    })?;

    for row in rows {
        let (job_id, name, title, printer_name, paper_name, created_at, updated_at) = row?;
        let workspace_path = workspace_path(app_support_path, &job_id);
        ensure_directory(Path::new(&workspace_path))?;

        connection.execute(
            r#"
            INSERT OR IGNORE INTO new_profile_jobs (
                id,
                workspace_path,
                profile_name,
                printer_id,
                paper_id,
                media_setting,
                quality_mode,
                print_path_notes,
                measurement_notes,
                measurement_observer,
                measurement_illuminant,
                measurement_mode,
                patch_count,
                improve_neutrals,
                use_existing_profile_planning,
                planning_profile_id,
                print_without_color_management,
                drying_time_minutes,
                printed_at,
                drying_ready_at,
                measurement_source_path,
                scan_file_path,
                has_measurement_checkpoint,
                latest_error,
                published_profile_id,
                created_at,
                updated_at
            )
            VALUES (?1, ?2, ?3, NULL, NULL, '', '', '', '', '1931_2', 'D50', 'strip', 836, 0, 0, NULL, 1, 120, NULL, NULL, NULL, NULL, 0, NULL, NULL, ?4, ?5)
            "#,
            params![
                &job_id,
                &workspace_path,
                if name.is_empty() { title.clone() } else { name.clone() },
                &created_at,
                &updated_at
            ],
        )?;

        let effective_title = if title.is_empty() {
            if name.is_empty() {
                "New Profile".to_string()
            } else {
                name.clone()
            }
        } else {
            title.clone()
        };
        let effective_profile_name = if name.is_empty() {
            effective_title.clone()
        } else {
            name
        };
        let stage = decode_workflow_stage(&connection.query_row(
            "SELECT stage FROM jobs WHERE id = ?1",
            params![&job_id],
            |row| row.get::<_, String>(0),
        )?);
        let normalized_stage = if matches!(stage, WorkflowStage::Completed) {
            WorkflowStage::Review
        } else {
            stage
        };
        update_job_summary(
            connection,
            &job_id,
            normalized_stage,
            &connection.query_row(
                "SELECT status FROM jobs WHERE id = ?1",
                params![&job_id],
                |row| row.get::<_, String>(0),
            )?,
            &connection.query_row(
                "SELECT next_action FROM jobs WHERE id = ?1",
                params![&job_id],
                |row| row.get::<_, String>(0),
            )?,
            &effective_profile_name,
            &printer_name,
            &paper_name,
        )?;
    }

    Ok(())
}

fn ensure_column(
    connection: &Connection,
    table_name: &str,
    column_name: &str,
    column_spec: &str,
) -> EngineResult<()> {
    if table_has_column(connection, table_name, column_name)? {
        return Ok(());
    }

    connection.execute(
        &format!("ALTER TABLE {table_name} ADD COLUMN {column_name} {column_spec}"),
        [],
    )?;

    Ok(())
}

fn table_has_column(
    connection: &Connection,
    table_name: &str,
    column_name: &str,
) -> EngineResult<bool> {
    let pragma = format!("PRAGMA table_info({table_name})");
    let mut statement = connection.prepare(&pragma)?;
    let rows = statement.query_map([], |row| row.get::<_, String>(1))?;

    for row in rows {
        if row? == column_name {
            return Ok(true);
        }
    }

    Ok(false)
}

fn load_setting(connection: &Connection, key: &str) -> EngineResult<Option<String>> {
    connection
        .query_row(
            "SELECT value FROM app_settings WHERE key = ?1",
            params![key],
            |row| row.get(0),
        )
        .optional()
        .map_err(Into::into)
}

fn encode_toolchain_state(state: &ToolchainState) -> &'static str {
    match state {
        ToolchainState::Ready => "ready",
        ToolchainState::Partial => "partial",
        ToolchainState::NotFound => "not_found",
    }
}

fn encode_workflow_stage(stage: &WorkflowStage) -> &'static str {
    match stage {
        WorkflowStage::Context => "context",
        WorkflowStage::Target => "target",
        WorkflowStage::Print => "print",
        WorkflowStage::Drying => "drying",
        WorkflowStage::Measure => "measure",
        WorkflowStage::Build => "build",
        WorkflowStage::Review => "review",
        WorkflowStage::Publish => "publish",
        WorkflowStage::Completed => "completed",
        WorkflowStage::Blocked => "blocked",
        WorkflowStage::Failed => "failed",
    }
}

fn decode_workflow_stage(value: &str) -> WorkflowStage {
    match value {
        "context" => WorkflowStage::Context,
        "target" => WorkflowStage::Target,
        "print" => WorkflowStage::Print,
        "drying" => WorkflowStage::Drying,
        "measure" => WorkflowStage::Measure,
        "build" => WorkflowStage::Build,
        "review" => WorkflowStage::Review,
        "publish" => WorkflowStage::Publish,
        "completed" => WorkflowStage::Completed,
        "blocked" => WorkflowStage::Blocked,
        "failed" => WorkflowStage::Failed,
        _ => WorkflowStage::Context,
    }
}

fn encode_measurement_mode(mode: &MeasurementMode) -> &'static str {
    match mode {
        MeasurementMode::Strip => "strip",
        MeasurementMode::Patch => "patch",
        MeasurementMode::ScanFile => "scan_file",
    }
}

fn decode_measurement_mode(value: &str) -> MeasurementMode {
    match value {
        "patch" => MeasurementMode::Patch,
        "scan_file" => MeasurementMode::ScanFile,
        _ => MeasurementMode::Strip,
    }
}

fn encode_artifact_kind(kind: &ArtifactKind) -> &'static str {
    match kind {
        ArtifactKind::Ti1 => "ti1",
        ArtifactKind::Ti2 => "ti2",
        ArtifactKind::PrintableChart => "printable_chart",
        ArtifactKind::ChartTemplate => "chart_template",
        ArtifactKind::Measurement => "measurement",
        ArtifactKind::IccProfile => "icc_profile",
        ArtifactKind::Verification => "verification",
        ArtifactKind::Diagnostic => "diagnostic",
        ArtifactKind::Working => "working",
    }
}

fn decode_artifact_kind(value: &str) -> ArtifactKind {
    match value {
        "ti1" => ArtifactKind::Ti1,
        "ti2" => ArtifactKind::Ti2,
        "printable_chart" => ArtifactKind::PrintableChart,
        "chart_template" => ArtifactKind::ChartTemplate,
        "measurement" => ArtifactKind::Measurement,
        "icc_profile" => ArtifactKind::IccProfile,
        "verification" => ArtifactKind::Verification,
        "diagnostic" => ArtifactKind::Diagnostic,
        _ => ArtifactKind::Working,
    }
}

fn decode_command_run_state(value: &str) -> CommandRunState {
    match value {
        "succeeded" => CommandRunState::Succeeded,
        "failed" => CommandRunState::Failed,
        _ => CommandRunState::Running,
    }
}

fn encode_command_stream(stream: &CommandStream) -> &'static str {
    match stream {
        CommandStream::Stdout => "stdout",
        CommandStream::Stderr => "stderr",
        CommandStream::System => "system",
    }
}

fn decode_command_stream(value: &str) -> CommandStream {
    match value {
        "stdout" => CommandStream::Stdout,
        "stderr" => CommandStream::Stderr,
        _ => CommandStream::System,
    }
}

fn encode_bool(value: bool) -> i64 {
    if value { 1 } else { 0 }
}

fn decode_bool(value: i64) -> bool {
    value != 0
}

fn encode_json<T: serde::Serialize + ?Sized>(value: &T) -> EngineResult<String> {
    Ok(serde_json::to_string(value)?)
}

fn decode_json<T: serde::de::DeserializeOwned + Default>(value: &str) -> T {
    serde_json::from_str(value).unwrap_or_default()
}

fn display_printer_name(make_model: &str, nickname: &str) -> String {
    let make_model = trim(make_model);
    let nickname = trim(nickname);
    if nickname.is_empty() {
        make_model
    } else {
        nickname
    }
}

fn display_paper_name(vendor_product_name: &str, surface_class: &str) -> String {
    let vendor_product_name = trim(vendor_product_name);
    let surface_class = trim(surface_class);
    if surface_class.is_empty() {
        vendor_product_name
    } else {
        format!("{vendor_product_name} ({surface_class})")
    }
}

fn build_stage_timeline(current_stage: &str) -> Vec<WorkflowStageSummary> {
    let current = decode_workflow_stage(current_stage);
    let ordered = [
        (WorkflowStage::Context, "Context"),
        (WorkflowStage::Target, "Target"),
        (WorkflowStage::Print, "Print"),
        (WorkflowStage::Drying, "Drying"),
        (WorkflowStage::Measure, "Measure"),
        (WorkflowStage::Build, "Build"),
        (WorkflowStage::Review, "Review"),
        (WorkflowStage::Publish, "Publish"),
    ];

    ordered
        .iter()
        .map(|(stage, title)| WorkflowStageSummary {
            stage: stage.clone(),
            title: (*title).to_string(),
            state: match current {
                WorkflowStage::Failed | WorkflowStage::Blocked => {
                    if stage_index(stage) < stage_index(&current) {
                        WorkflowStageState::Completed
                    } else if stage_index(stage) == stage_index(&WorkflowStage::Review) {
                        WorkflowStageState::Blocked
                    } else {
                        WorkflowStageState::Upcoming
                    }
                }
                WorkflowStage::Completed => WorkflowStageState::Completed,
                _ if stage_index(stage) < stage_index(&current) => WorkflowStageState::Completed,
                _ if *stage == current => WorkflowStageState::Current,
                _ => WorkflowStageState::Upcoming,
            },
        })
        .collect()
}

fn stage_index(stage: &WorkflowStage) -> usize {
    match stage {
        WorkflowStage::Context => 0,
        WorkflowStage::Target => 1,
        WorkflowStage::Print => 2,
        WorkflowStage::Drying => 3,
        WorkflowStage::Measure => 4,
        WorkflowStage::Build => 5,
        WorkflowStage::Review => 6,
        WorkflowStage::Publish => 7,
        WorkflowStage::Completed => 8,
        WorkflowStage::Blocked => 9,
        WorkflowStage::Failed => 10,
    }
}

fn trim(value: &str) -> String {
    value.trim().to_string()
}

fn trimmed_strings(values: Vec<String>) -> Vec<String> {
    values
        .into_iter()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .collect()
}

fn job_timestamp_seed() -> i64 {
    Utc::now()
        .timestamp_nanos_opt()
        .unwrap_or_else(|| Utc::now().timestamp_micros() * 1_000)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{InstrumentConnectionState, SaveNewProfileContextInput};
    use tempfile::tempdir;

    fn build_config(root: &Path) -> EngineConfig {
        EngineConfig {
            app_support_path: root.join("app-support").to_string_lossy().to_string(),
            database_path: root
                .join("app-support/argyllux.sqlite")
                .to_string_lossy()
                .to_string(),
            log_path: root.join("logs/engine.log").to_string_lossy().to_string(),
            argyll_override_path: None,
            additional_search_roots: Vec::new(),
        }
    }

    #[test]
    fn dashboard_snapshot_returns_persisted_jobs() {
        let temp = tempdir().unwrap();
        let config = build_config(temp.path());
        std::fs::create_dir_all(temp.path().join("app-support")).unwrap();

        initialize_database(&config).unwrap();
        let printer = create_printer(
            &config.database_path,
            &CreatePrinterInput {
                make_model: "Epson P900".to_string(),
                nickname: "P900".to_string(),
                transport_style: "Sheet-fed".to_string(),
                supported_quality_modes: vec!["1440 dpi".to_string()],
                monochrome_path_notes: "".to_string(),
                notes: "".to_string(),
            },
        )
        .unwrap();
        let paper = create_paper(
            &config.database_path,
            &CreatePaperInput {
                vendor_product_name: "Canson Rag".to_string(),
                surface_class: "Matte".to_string(),
                weight_thickness: "".to_string(),
                oba_fluorescence_notes: "".to_string(),
                notes: "".to_string(),
            },
        )
        .unwrap();

        let job = create_new_profile_draft(
            &config.database_path,
            &config.app_support_path,
            &CreateNewProfileDraftInput {
                profile_name: Some("P900 Rag v1".to_string()),
                printer_id: Some(printer.id.clone()),
                paper_id: Some(paper.id.clone()),
            },
        )
        .unwrap();
        save_new_profile_context(
            &config.database_path,
            &SaveNewProfileContextInput {
                job_id: job.id.clone(),
                profile_name: "P900 Rag v1".to_string(),
                printer_id: Some(printer.id.clone()),
                paper_id: Some(paper.id.clone()),
                media_setting: "Premium Luster".to_string(),
                quality_mode: "1440 dpi".to_string(),
                print_path_notes: "".to_string(),
                measurement_notes: "".to_string(),
                measurement_observer: "1931_2".to_string(),
                measurement_illuminant: "D50".to_string(),
                measurement_mode: MeasurementMode::Strip,
            },
        )
        .unwrap();

        let snapshot = load_dashboard_snapshot(&config.database_path).unwrap();

        assert_eq!(snapshot.jobs_count, 1);
        assert_eq!(snapshot.active_work_items.len(), 1);
        assert_eq!(snapshot.active_work_items[0].id, job.id);
        assert_eq!(snapshot.active_work_items[0].stage, WorkflowStage::Target);
        assert_eq!(
            snapshot.instrument_status.state,
            InstrumentConnectionState::Disconnected
        );
        assert_eq!(
            snapshot.instrument_status.label,
            "No Instrument Connected".to_string()
        );
    }

    #[test]
    fn delete_new_profile_job_removes_active_work_and_workspace() {
        let temp = tempdir().unwrap();
        let config = build_config(temp.path());
        std::fs::create_dir_all(temp.path().join("app-support")).unwrap();

        initialize_database(&config).unwrap();

        let job = create_new_profile_draft(
            &config.database_path,
            &config.app_support_path,
            &CreateNewProfileDraftInput {
                profile_name: Some("Delete Me".to_string()),
                printer_id: None,
                paper_id: None,
            },
        )
        .unwrap();

        let workspace_path = Path::new(&job.workspace_path);
        assert!(workspace_path.exists());

        let result = delete_new_profile_job(&config.database_path, &job.id).unwrap();
        assert!(result.success);

        let snapshot = load_dashboard_snapshot(&config.database_path).unwrap();
        assert!(snapshot.active_work_items.is_empty());
        assert!(!workspace_path.exists());

        let connection = open_connection(&config.database_path).unwrap();
        let jobs_count: i64 = connection
            .query_row("SELECT COUNT(*) FROM jobs", [], |row| row.get(0))
            .unwrap();
        let new_profile_jobs_count: i64 = connection
            .query_row("SELECT COUNT(*) FROM new_profile_jobs", [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(jobs_count, 0);
        assert_eq!(new_profile_jobs_count, 0);
    }

    #[test]
    fn migration_upgrades_existing_jobs_into_new_profile_jobs() {
        let temp = tempdir().unwrap();
        let database_path = temp.path().join("legacy.sqlite");
        let connection = Connection::open(&database_path).unwrap();

        connection
            .execute_batch(
                r#"
                CREATE TABLE app_settings (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE TABLE toolchain_status_cache (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    state TEXT NOT NULL,
                    resolved_install_path TEXT,
                    discovered_executables TEXT NOT NULL,
                    missing_executables TEXT NOT NULL,
                    last_validation_time TEXT
                );
                CREATE TABLE jobs (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                PRAGMA user_version = 1;
                INSERT INTO jobs (id, name, status, created_at, updated_at)
                VALUES ('job-1', 'Legacy Profile', 'setup', '2026-04-19T00:00:00Z', '2026-04-19T00:00:00Z');
                "#,
            )
            .unwrap();

        let config = EngineConfig {
            app_support_path: temp
                .path()
                .join("app-support")
                .to_string_lossy()
                .to_string(),
            database_path: database_path.to_string_lossy().to_string(),
            log_path: temp
                .path()
                .join("logs/engine.log")
                .to_string_lossy()
                .to_string(),
            argyll_override_path: None,
            additional_search_roots: Vec::new(),
        };

        let status = initialize_database(&config).unwrap();
        assert!(status.migrations_applied);

        let upgraded = Connection::open(database_path).unwrap();
        let version: i64 = upgraded
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .unwrap();
        assert_eq!(version, DATABASE_VERSION);

        let workspace_path: String = upgraded
            .query_row(
                "SELECT workspace_path FROM new_profile_jobs WHERE id = 'job-1'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert!(workspace_path.contains("job-1"));
    }

    #[test]
    fn printer_and_paper_round_trip() {
        let temp = tempdir().unwrap();
        let config = build_config(temp.path());
        std::fs::create_dir_all(temp.path().join("app-support")).unwrap();
        initialize_database(&config).unwrap();

        let printer = create_printer(
            &config.database_path,
            &CreatePrinterInput {
                make_model: "Epson P900".to_string(),
                nickname: "Studio P900".to_string(),
                transport_style: "Sheet-fed".to_string(),
                supported_quality_modes: vec!["1440 dpi".to_string(), "2880 dpi".to_string()],
                monochrome_path_notes: "ABW".to_string(),
                notes: "North wall".to_string(),
            },
        )
        .unwrap();
        let paper = create_paper(
            &config.database_path,
            &CreatePaperInput {
                vendor_product_name: "Canson Rag".to_string(),
                surface_class: "Matte".to_string(),
                weight_thickness: "310 gsm".to_string(),
                oba_fluorescence_notes: "Low OBA".to_string(),
                notes: "".to_string(),
            },
        )
        .unwrap();

        let printers = list_printers(&config.database_path).unwrap();
        let papers = list_papers(&config.database_path).unwrap();

        assert_eq!(printers.len(), 1);
        assert_eq!(papers.len(), 1);
        assert_eq!(printers[0].id, printer.id);
        assert_eq!(papers[0].id, paper.id);
    }
}
