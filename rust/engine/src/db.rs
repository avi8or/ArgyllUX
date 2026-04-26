use crate::diagnostics;
use crate::model::{
    ActiveWorkItem, ArtifactKind, ColorantFamily, CommandRunState, CommandStream,
    CreateNewProfileDraftInput, CreatePaperInput, CreatePrinterInput,
    CreatePrinterPaperPresetInput, DashboardSnapshot, DeleteResult, DiagnosticCategory,
    DiagnosticEventFilter, DiagnosticEventInput, DiagnosticEventRecord, DiagnosticLevel,
    DiagnosticPrivacy, DiagnosticsSummary, EngineConfig, InstrumentStatus, JobArtifactRecord,
    JobCommandEventRecord, JobCommandRecord, MeasurementMode, MeasurementStatusRecord,
    NewProfileContextRecord, NewProfileJobDetail, PaperRecord, PaperThicknessUnit, PaperWeightUnit,
    PrintSettingsRecord, PrinterPaperPresetRecord, PrinterProfileRecord, PrinterRecord,
    ReviewSummaryRecord, SaveNewProfileContextInput, SavePrintSettingsInput,
    SaveTargetSettingsInput, StartMeasurementInput, TargetSettingsRecord, ToolchainState,
    ToolchainStatus, UpdatePaperInput, UpdatePrinterInput, UpdatePrinterPaperPresetInput,
    WorkflowStage, WorkflowStageState, WorkflowStageSummary,
};
use crate::support::{EngineResult, ensure_directory, iso_timestamp};
use chrono::{Duration, Utc};
use rusqlite::{Connection, OptionalExtension, params, params_from_iter, types::Value};
use std::path::Path;

const TOOLCHAIN_OVERRIDE_KEY: &str = "toolchain.override_path";
pub(crate) const DATABASE_VERSION: i64 = 6;

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
    pub printer_manufacturer: String,
    pub printer_model: String,
    pub workspace_path: String,
    pub print_path: String,
    pub media_setting: String,
    pub quality_mode: String,
    pub colorant_family: ColorantFamily,
    pub channel_count: u32,
    pub channel_labels: Vec<String>,
    pub total_ink_limit_percent: Option<u32>,
    pub black_ink_limit_percent: Option<u32>,
    pub measurement_observer: String,
    pub measurement_mode: MeasurementMode,
    pub patch_count: u32,
    pub improve_neutrals: bool,
    pub planning_profile_path: Option<String>,
    pub measurement_source_path: Option<String>,
    pub scan_file_path: Option<String>,
    pub has_measurement_checkpoint: bool,
}

#[derive(Debug, Clone)]
struct UntouchedBlankDraftCandidate {
    id: String,
    workspace_path: String,
}

#[derive(Debug, Clone)]
struct ResumableNewProfileJobCandidate {
    id: String,
    workspace_path: String,
    has_running_command: bool,
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

    Ok(diagnostics::event_record_from_input(
        id, timestamp, sanitized,
    ))
}

pub fn list_diagnostic_events(
    database_path: &str,
    filter: &DiagnosticEventFilter,
) -> EngineResult<Vec<DiagnosticEventRecord>> {
    let connection = open_connection(database_path)?;
    let limit = filter.limit.clamp(1, 500);
    let (where_clause, mut query_params) = diagnostic_filter_sql(filter);
    let mut query = r#"
            SELECT id, timestamp, level, category, source, message, details_json, privacy,
                   job_id, command_id, profile_id, issue_case_id, duration_ms, operation_id, parent_operation_id
            FROM diagnostic_events
"#
    .to_string();

    if !where_clause.is_empty() {
        query.push_str(" WHERE ");
        query.push_str(&where_clause);
    }

    query.push_str(" ORDER BY timestamp DESC LIMIT ?");
    query_params.push(Value::Integer(i64::from(limit)));

    let rows = connection
        .prepare(&query)?
        .query_map(
            params_from_iter(query_params.iter()),
            diagnostic_event_from_row,
        )?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(rows)
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
    let cutoff =
        (Utc::now() - Duration::days(diagnostics::DEFAULT_RETENTION_DAYS as i64)).to_rfc3339();
    let deleted = connection.execute(
        "DELETE FROM diagnostic_events WHERE timestamp < ?1",
        params![cutoff],
    )?;
    Ok(deleted as u32)
}

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

fn diagnostic_filter_sql(filter: &DiagnosticEventFilter) -> (String, Vec<Value>) {
    let mut predicates = Vec::new();
    let mut params = Vec::new();

    if filter.errors_only {
        predicates.push("level IN ('error', 'critical')".to_string());
    }

    add_diagnostic_in_predicate(
        &mut predicates,
        &mut params,
        "level",
        filter.levels.iter().map(encode_diagnostic_level),
    );
    add_diagnostic_in_predicate(
        &mut predicates,
        &mut params,
        "category",
        filter.categories.iter().map(encode_diagnostic_category),
    );

    if let Some(job_id) = filter.job_id.as_deref() {
        predicates.push("job_id = ?".to_string());
        params.push(Value::Text(job_id.to_string()));
    }

    if let Some(profile_id) = filter.profile_id.as_deref() {
        predicates.push("profile_id = ?".to_string());
        params.push(Value::Text(profile_id.to_string()));
    }

    if let Some(since) = filter.since_timestamp.as_deref() {
        predicates.push("timestamp >= ?".to_string());
        params.push(Value::Text(since.to_string()));
    }

    if let Some(until) = filter.until_timestamp.as_deref() {
        predicates.push("timestamp <= ?".to_string());
        params.push(Value::Text(until.to_string()));
    }

    if let Some(search_text) = filter.search_text.as_deref() {
        let needle = search_text.trim().to_ascii_lowercase();
        if !needle.is_empty() {
            let pattern = format!("%{}%", escape_sql_like(&needle));
            predicates.push(
                "(LOWER(source) LIKE ? ESCAPE '\\' OR LOWER(message) LIKE ? ESCAPE '\\' OR LOWER(details_json) LIKE ? ESCAPE '\\' OR LOWER(timestamp) LIKE ? ESCAPE '\\')"
                    .to_string(),
            );
            params.push(Value::Text(pattern.clone()));
            params.push(Value::Text(pattern.clone()));
            params.push(Value::Text(pattern.clone()));
            params.push(Value::Text(pattern));
        }
    }

    (predicates.join(" AND "), params)
}

fn add_diagnostic_in_predicate(
    predicates: &mut Vec<String>,
    params: &mut Vec<Value>,
    column: &str,
    values: impl Iterator<Item = &'static str>,
) {
    let values = values.collect::<Vec<_>>();
    if values.is_empty() {
        return;
    }

    let placeholders = std::iter::repeat_n("?", values.len())
        .collect::<Vec<_>>()
        .join(", ");
    predicates.push(format!("{column} IN ({placeholders})"));

    for value in values {
        params.push(Value::Text(value.to_string()));
    }
}

fn escape_sql_like(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len());

    for character in value.chars() {
        match character {
            '%' | '_' | '\\' => {
                escaped.push('\\');
                escaped.push(character);
            }
            _ => escaped.push(character),
        }
    }

    escaped
}

fn diagnostic_count(connection: &Connection, level: Option<&str>) -> EngineResult<u32> {
    let count: i64 = match level {
        Some(level) => connection.query_row(
            "SELECT COUNT(*) FROM diagnostic_events WHERE level = ?1",
            params![level],
            |row| row.get(0),
        )?,
        None => connection.query_row("SELECT COUNT(*) FROM diagnostic_events", [], |row| {
            row.get(0)
        })?,
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

pub fn load_dashboard_snapshot(database_path: &str) -> EngineResult<DashboardSnapshot> {
    let mut connection = open_connection(database_path)?;
    collapse_untouched_blank_new_profile_drafts(&mut connection)?;
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
    let manufacturer = trim(&input.manufacturer);
    let model = trim(&input.model);
    validate_printer_identity(&manufacturer, &model)?;
    let (channel_count, channel_labels) = normalize_channel_configuration(
        &input.colorant_family,
        input.channel_count,
        input.channel_labels.clone(),
    )?;
    let supported_media_settings =
        normalized_catalog_values(input.supported_media_settings.clone());
    let supported_quality_modes = normalized_catalog_values(input.supported_quality_modes.clone());
    let display_name = display_printer_name(&manufacturer, &model, &input.nickname);

    connection.execute(
        r#"
        INSERT INTO printers (
            id,
            manufacturer,
            model,
            nickname,
            transport_style,
            colorant_family,
            channel_count,
            channel_labels,
            supported_media_settings,
            supported_quality_modes,
            monochrome_path_notes,
            notes,
            created_at,
            updated_at
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
        "#,
        params![
            &id,
            &manufacturer,
            &model,
            trim(&input.nickname),
            trim(&input.transport_style),
            encode_colorant_family(&input.colorant_family),
            channel_count,
            encode_json(&channel_labels)?,
            encode_json(&supported_media_settings)?,
            encode_json(&supported_quality_modes)?,
            trim(&input.monochrome_path_notes),
            trim(&input.notes),
            &now,
            &now
        ],
    )?;

    Ok(PrinterRecord {
        id,
        manufacturer,
        model,
        nickname: trim(&input.nickname),
        transport_style: trim(&input.transport_style),
        colorant_family: input.colorant_family.clone(),
        channel_count,
        channel_labels,
        supported_media_settings,
        supported_quality_modes,
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
    let manufacturer = trim(&input.manufacturer);
    let model = trim(&input.model);
    validate_printer_identity(&manufacturer, &model)?;
    let (channel_count, channel_labels) = normalize_channel_configuration(
        &input.colorant_family,
        input.channel_count,
        input.channel_labels.clone(),
    )?;
    let supported_media_settings =
        normalized_catalog_values(input.supported_media_settings.clone());
    let supported_quality_modes = normalized_catalog_values(input.supported_quality_modes.clone());

    connection.execute(
        r#"
        UPDATE printers
        SET
            manufacturer = ?2,
            model = ?3,
            nickname = ?4,
            transport_style = ?5,
            colorant_family = ?6,
            channel_count = ?7,
            channel_labels = ?8,
            supported_media_settings = ?9,
            supported_quality_modes = ?10,
            monochrome_path_notes = ?11,
            notes = ?12,
            updated_at = ?13
        WHERE id = ?1
        "#,
        params![
            &input.id,
            &manufacturer,
            &model,
            trim(&input.nickname),
            trim(&input.transport_style),
            encode_colorant_family(&input.colorant_family),
            channel_count,
            encode_json(&channel_labels)?,
            encode_json(&supported_media_settings)?,
            encode_json(&supported_quality_modes)?,
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
    let manufacturer = trim(&input.manufacturer);
    let paper_line = trim(&input.paper_line);
    validate_paper_identity(&paper_line)?;
    let display_name = display_paper_name(&manufacturer, &paper_line, &input.surface_class);

    connection.execute(
        r#"
        INSERT INTO papers (
            id,
            manufacturer,
            paper_line,
            surface_class,
            basis_weight_value,
            basis_weight_unit,
            thickness_value,
            thickness_unit,
            surface_texture,
            base_material,
            media_color,
            opacity,
            whiteness,
            oba_content,
            ink_compatibility,
            notes,
            created_at,
            updated_at
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18)
        "#,
        params![
            &id,
            &manufacturer,
            &paper_line,
            trim(&input.surface_class),
            trim(&input.basis_weight_value),
            encode_paper_weight_unit(&input.basis_weight_unit),
            trim(&input.thickness_value),
            encode_paper_thickness_unit(&input.thickness_unit),
            trim(&input.surface_texture),
            trim(&input.base_material),
            trim(&input.media_color),
            trim(&input.opacity),
            trim(&input.whiteness),
            trim(&input.oba_content),
            trim(&input.ink_compatibility),
            trim(&input.notes),
            &now,
            &now
        ],
    )?;

    Ok(PaperRecord {
        id,
        manufacturer,
        paper_line,
        surface_class: trim(&input.surface_class),
        basis_weight_value: trim(&input.basis_weight_value),
        basis_weight_unit: input.basis_weight_unit.clone(),
        thickness_value: trim(&input.thickness_value),
        thickness_unit: input.thickness_unit.clone(),
        surface_texture: trim(&input.surface_texture),
        base_material: trim(&input.base_material),
        media_color: trim(&input.media_color),
        opacity: trim(&input.opacity),
        whiteness: trim(&input.whiteness),
        oba_content: trim(&input.oba_content),
        ink_compatibility: trim(&input.ink_compatibility),
        notes: trim(&input.notes),
        display_name,
        created_at: now.clone(),
        updated_at: now,
    })
}

pub fn update_paper(database_path: &str, input: &UpdatePaperInput) -> EngineResult<PaperRecord> {
    let connection = open_connection(database_path)?;
    let now = iso_timestamp();
    let manufacturer = trim(&input.manufacturer);
    let paper_line = trim(&input.paper_line);
    validate_paper_identity(&paper_line)?;

    connection.execute(
        r#"
        UPDATE papers
        SET
            manufacturer = ?2,
            paper_line = ?3,
            surface_class = ?4,
            basis_weight_value = ?5,
            basis_weight_unit = ?6,
            thickness_value = ?7,
            thickness_unit = ?8,
            surface_texture = ?9,
            base_material = ?10,
            media_color = ?11,
            opacity = ?12,
            whiteness = ?13,
            oba_content = ?14,
            ink_compatibility = ?15,
            notes = ?16,
            updated_at = ?17
        WHERE id = ?1
        "#,
        params![
            &input.id,
            &manufacturer,
            &paper_line,
            trim(&input.surface_class),
            trim(&input.basis_weight_value),
            encode_paper_weight_unit(&input.basis_weight_unit),
            trim(&input.thickness_value),
            encode_paper_thickness_unit(&input.thickness_unit),
            trim(&input.surface_texture),
            trim(&input.base_material),
            trim(&input.media_color),
            trim(&input.opacity),
            trim(&input.whiteness),
            trim(&input.oba_content),
            trim(&input.ink_compatibility),
            trim(&input.notes),
            &now
        ],
    )?;

    load_paper(&connection, &input.id)?.ok_or_else(|| "paper not found".into())
}

pub fn list_printer_paper_presets(
    database_path: &str,
) -> EngineResult<Vec<PrinterPaperPresetRecord>> {
    let connection = open_connection(database_path)?;
    load_printer_paper_presets(&connection)
}

pub fn create_printer_paper_preset(
    database_path: &str,
    input: &CreatePrinterPaperPresetInput,
) -> EngineResult<PrinterPaperPresetRecord> {
    let connection = open_connection(database_path)?;
    let id = format!("preset-{}", job_timestamp_seed());
    let now = iso_timestamp();
    let printer = load_printer(&connection, &input.printer_id)?.ok_or("printer not found")?;
    let _paper = load_paper(&connection, &input.paper_id)?.ok_or("paper not found")?;
    let validated = validate_printer_paper_preset(
        &printer,
        trim(&input.media_setting),
        trim(&input.quality_mode),
        input.total_ink_limit_percent,
        input.black_ink_limit_percent,
    )?;
    let label = trim(&input.label);
    let print_path = trim(&input.print_path);
    let display_name = display_printer_paper_preset_name(
        &label,
        &print_path,
        &validated.media_setting,
        &validated.quality_mode,
    );

    connection.execute(
        r#"
        INSERT INTO printer_paper_presets (
            id,
            printer_id,
            paper_id,
            label,
            print_path,
            media_setting,
            quality_mode,
            total_ink_limit_percent,
            black_ink_limit_percent,
            notes,
            created_at,
            updated_at
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
        "#,
        params![
            &id,
            &input.printer_id,
            &input.paper_id,
            &label,
            &print_path,
            &validated.media_setting,
            &validated.quality_mode,
            validated.total_ink_limit_percent.map(|value| value as i64),
            validated.black_ink_limit_percent.map(|value| value as i64),
            trim(&input.notes),
            &now,
            &now
        ],
    )?;

    Ok(PrinterPaperPresetRecord {
        id,
        printer_id: input.printer_id.clone(),
        paper_id: input.paper_id.clone(),
        label,
        print_path,
        media_setting: validated.media_setting,
        quality_mode: validated.quality_mode,
        total_ink_limit_percent: validated.total_ink_limit_percent,
        black_ink_limit_percent: validated.black_ink_limit_percent,
        notes: trim(&input.notes),
        display_name,
        created_at: now.clone(),
        updated_at: now,
    })
}

pub fn update_printer_paper_preset(
    database_path: &str,
    input: &UpdatePrinterPaperPresetInput,
) -> EngineResult<PrinterPaperPresetRecord> {
    let connection = open_connection(database_path)?;
    let now = iso_timestamp();
    let printer = load_printer(&connection, &input.printer_id)?.ok_or("printer not found")?;
    let _paper = load_paper(&connection, &input.paper_id)?.ok_or("paper not found")?;
    let validated = validate_printer_paper_preset(
        &printer,
        trim(&input.media_setting),
        trim(&input.quality_mode),
        input.total_ink_limit_percent,
        input.black_ink_limit_percent,
    )?;

    connection.execute(
        r#"
        UPDATE printer_paper_presets
        SET
            printer_id = ?2,
            paper_id = ?3,
            label = ?4,
            print_path = ?5,
            media_setting = ?6,
            quality_mode = ?7,
            total_ink_limit_percent = ?8,
            black_ink_limit_percent = ?9,
            notes = ?10,
            updated_at = ?11
        WHERE id = ?1
        "#,
        params![
            &input.id,
            &input.printer_id,
            &input.paper_id,
            trim(&input.label),
            trim(&input.print_path),
            &validated.media_setting,
            &validated.quality_mode,
            validated.total_ink_limit_percent.map(|value| value as i64),
            validated.black_ink_limit_percent.map(|value| value as i64),
            trim(&input.notes),
            &now
        ],
    )?;

    load_printer_paper_preset(&connection, &input.id)?
        .ok_or_else(|| "printer-paper preset not found".into())
}

pub fn list_printer_profiles(database_path: &str) -> EngineResult<Vec<PrinterProfileRecord>> {
    let connection = open_connection(database_path)?;
    load_printer_profiles(&connection)
}

pub fn delete_printer_profile(database_path: &str, profile_id: &str) -> EngineResult<DeleteResult> {
    let connection = open_connection(database_path)?;
    let profile = match load_printer_profile(&connection, profile_id)? {
        Some(profile) => profile,
        None => {
            return Ok(DeleteResult {
                success: false,
                message: "Printer Profile was not found.".to_string(),
            });
        }
    };
    let source_job = connection
        .query_row(
            r#"
            SELECT id
            FROM new_profile_jobs
            WHERE published_profile_id = ?1
            ORDER BY updated_at DESC, created_at DESC, id DESC
            LIMIT 1
            "#,
            params![profile_id],
            |row| row.get::<_, String>(0),
        )
        .optional()?
        .map(|job_id| {
            load_new_profile_job_detail_from_connection(&connection, &job_id)
                .map(|detail| (job_id, detail))
        })
        .transpose()?
        .or({
            if connection.query_row(
                "SELECT EXISTS(SELECT 1 FROM jobs WHERE id = ?1)",
                params![&profile.created_from_job_id],
                |row| row.get::<_, i64>(0),
            )? == 1
            {
                Some((
                    profile.created_from_job_id.clone(),
                    load_new_profile_job_detail_from_connection(
                        &connection,
                        &profile.created_from_job_id,
                    )?,
                ))
            } else {
                None
            }
        });
    let now = iso_timestamp();

    connection.execute(
        r#"
        UPDATE new_profile_jobs
        SET
            published_profile_id = NULL,
            updated_at = ?2
        WHERE published_profile_id = ?1
        "#,
        params![profile_id, &now],
    )?;
    connection.execute(
        r#"
        UPDATE new_profile_jobs
        SET
            planning_profile_id = NULL,
            updated_at = ?2
        WHERE planning_profile_id = ?1
        "#,
        params![profile_id, &now],
    )?;

    let deleted = connection.execute(
        "DELETE FROM printer_profiles WHERE id = ?1",
        params![profile_id],
    )?;

    if deleted == 0 {
        return Ok(DeleteResult {
            success: false,
            message: "Printer Profile was not found.".to_string(),
        });
    }

    // Reopen the source job only when it still exists. Corrupted or migrated
    // databases can retain a profile row after the originating job is gone.
    if let Some((source_job_id, source_job)) = source_job {
        update_job_summary(
            &connection,
            &source_job_id,
            WorkflowStage::Review,
            "review",
            "Publish the profile or return later",
            &source_job.profile_name,
            &source_job.printer_name,
            &source_job.paper_name,
        )?;
    }

    Ok(DeleteResult {
        success: true,
        message: String::new(),
    })
}

pub fn create_new_profile_draft(
    database_path: &str,
    app_support_path: &str,
    input: &CreateNewProfileDraftInput,
) -> EngineResult<NewProfileJobDetail> {
    let connection = open_connection(database_path)?;
    create_new_profile_draft_with_connection(&connection, app_support_path, input)
}

fn create_new_profile_draft_with_connection(
    connection: &Connection,
    app_support_path: &str,
    input: &CreateNewProfileDraftInput,
) -> EngineResult<NewProfileJobDetail> {
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
    let printer = input
        .printer_id
        .as_deref()
        .map(|printer_id| load_printer(connection, printer_id))
        .transpose()?
        .flatten();
    let paper = input
        .paper_id
        .as_deref()
        .map(|paper_id| load_paper(connection, paper_id))
        .transpose()?
        .flatten();
    let printer_name = printer
        .as_ref()
        .map(|printer| printer.display_name.clone())
        .unwrap_or_default();
    let paper_name = paper
        .as_ref()
        .map(|paper| paper.display_name.clone())
        .unwrap_or_default();
    let snapshot_colorant_family = printer
        .as_ref()
        .map(|printer| printer.colorant_family.clone())
        .unwrap_or(ColorantFamily::Cmyk);
    let snapshot_channel_count = printer
        .as_ref()
        .map(|printer| printer.channel_count)
        .unwrap_or(4);
    let snapshot_channel_labels = printer
        .as_ref()
        .map(|printer| printer.channel_labels.clone())
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
            printer_paper_preset_id,
            print_path,
            media_setting,
            quality_mode,
            colorant_family_snapshot,
            channel_count_snapshot,
            channel_labels_snapshot,
            total_ink_limit_percent_snapshot,
            black_ink_limit_percent_snapshot,
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
        VALUES (?1, ?2, ?3, ?4, ?5, NULL, '', '', '', ?6, ?7, ?8, NULL, NULL, '', '', '1931_2', 'D50', 'strip', 836, 0, 0, NULL, 1, 120, NULL, NULL, NULL, NULL, 0, NULL, NULL, ?9, ?10)
        "#,
        params![
            &id,
            &workspace_path,
            &profile_name,
            input.printer_id.as_deref(),
            input.paper_id.as_deref(),
            encode_colorant_family(&snapshot_colorant_family),
            snapshot_channel_count as i64,
            encode_json(&snapshot_channel_labels)?,
            &now,
            &now
        ],
    )?;

    load_new_profile_job_detail_from_connection(connection, &id)
}

pub fn resolve_new_profile_launch(
    database_path: &str,
    app_support_path: &str,
    input: &CreateNewProfileDraftInput,
) -> EngineResult<NewProfileJobDetail> {
    let mut connection = open_connection(database_path)?;
    let mut deleted_workspace_paths = Vec::new();

    let detail = {
        let transaction = connection.transaction()?;
        // New Profile is a single-active-work workflow. Launch resolution owns
        // duplicate cleanup so Swift entry points can simply ask to open it.
        let candidates = list_resumable_new_profile_job_candidates(&transaction)?;
        let retained = candidates
            .iter()
            .find(|candidate| candidate.has_running_command)
            .or_else(|| candidates.first())
            .cloned();

        for candidate in &candidates {
            if retained
                .as_ref()
                .is_some_and(|retained| retained.id == candidate.id)
            {
                continue;
            }

            if candidate.has_running_command {
                continue;
            }

            delete_new_profile_job_records(&transaction, &candidate.id)?;
            deleted_workspace_paths.push(candidate.workspace_path.clone());
        }

        let detail = if let Some(retained) = retained {
            load_new_profile_job_detail_from_connection(&transaction, &retained.id)?
        } else {
            create_new_profile_draft_with_connection(&transaction, app_support_path, input)?
        };

        transaction.commit()?;
        detail
    };

    for workspace_path in deleted_workspace_paths {
        remove_workspace_directory(&workspace_path);
    }

    Ok(detail)
}

pub fn load_new_profile_job_detail(
    database_path: &str,
    job_id: &str,
) -> EngineResult<NewProfileJobDetail> {
    let connection = open_connection(database_path)?;
    load_new_profile_job_detail_from_connection(&connection, job_id)
}

pub fn delete_new_profile_job(database_path: &str, job_id: &str) -> EngineResult<DeleteResult> {
    let mut connection = open_connection(database_path)?;
    let detail = load_new_profile_job_detail_from_connection(&connection, job_id)?;

    if detail.is_command_running {
        return Ok(DeleteResult {
            success: false,
            message: "Wait for the current Argyll command to finish before deleting this work."
                .to_string(),
        });
    }

    {
        let transaction = connection.transaction()?;
        delete_new_profile_job_records(&transaction, job_id)?;
        transaction.commit()?;
    }

    remove_workspace_directory(&detail.workspace_path);

    Ok(DeleteResult {
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
    let preset = input
        .printer_paper_preset_id
        .as_deref()
        .map(|preset_id| load_printer_paper_preset(&connection, preset_id))
        .transpose()?
        .flatten();
    let resolved_printer_id = input
        .printer_id
        .clone()
        .or_else(|| preset.as_ref().map(|record| record.printer_id.clone()));
    let resolved_paper_id = input
        .paper_id
        .clone()
        .or_else(|| preset.as_ref().map(|record| record.paper_id.clone()));
    let printer = resolved_printer_id
        .as_deref()
        .map(|printer_id| load_printer(&connection, printer_id))
        .transpose()?
        .flatten();
    let paper = resolved_paper_id
        .as_deref()
        .map(|paper_id| load_paper(&connection, paper_id))
        .transpose()?
        .flatten();
    if let Some(preset) = &preset {
        if resolved_printer_id.as_deref() != Some(preset.printer_id.as_str()) {
            return Err("Selected printer settings do not belong to the chosen printer.".into());
        }
        if resolved_paper_id.as_deref() != Some(preset.paper_id.as_str()) {
            return Err("Selected printer settings do not belong to the chosen paper.".into());
        }
    }
    let resolved_media_setting = if let Some(preset) = &preset {
        preset.media_setting.clone()
    } else {
        trim(&input.media_setting)
    };
    let resolved_print_path = if let Some(preset) = &preset {
        preset.print_path.clone()
    } else {
        trim(&input.print_path)
    };
    let resolved_quality_mode = if let Some(preset) = &preset {
        preset.quality_mode.clone()
    } else {
        trim(&input.quality_mode)
    };
    let (
        colorant_family,
        channel_count,
        channel_labels,
        total_ink_limit_percent,
        black_ink_limit_percent,
    ) = if let Some(printer) = &printer {
        validate_context_catalog_selection(
            printer,
            &resolved_media_setting,
            &resolved_quality_mode,
        )?;
        (
            printer.colorant_family.clone(),
            printer.channel_count,
            printer.channel_labels.clone(),
            preset
                .as_ref()
                .and_then(|record| record.total_ink_limit_percent),
            preset
                .as_ref()
                .and_then(|record| record.black_ink_limit_percent),
        )
    } else {
        (
            ColorantFamily::Cmyk,
            4,
            Vec::new(),
            preset
                .as_ref()
                .and_then(|record| record.total_ink_limit_percent),
            preset
                .as_ref()
                .and_then(|record| record.black_ink_limit_percent),
        )
    };
    let printer_name = printer
        .as_ref()
        .map(|record| record.display_name.clone())
        .unwrap_or_default();
    let paper_name = paper
        .as_ref()
        .map(|record| record.display_name.clone())
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
            printer_paper_preset_id = ?5,
            print_path = ?6,
            media_setting = ?7,
            quality_mode = ?8,
            colorant_family_snapshot = ?9,
            channel_count_snapshot = ?10,
            channel_labels_snapshot = ?11,
            total_ink_limit_percent_snapshot = ?12,
            black_ink_limit_percent_snapshot = ?13,
            print_path_notes = ?14,
            measurement_notes = ?15,
            measurement_observer = ?16,
            measurement_illuminant = ?17,
            measurement_mode = ?18,
            latest_error = NULL,
            updated_at = ?19
        WHERE id = ?1
        "#,
        params![
            &input.job_id,
            trim(&input.profile_name),
            resolved_printer_id.as_deref(),
            resolved_paper_id.as_deref(),
            input.printer_paper_preset_id.as_deref(),
            &resolved_print_path,
            &resolved_media_setting,
            &resolved_quality_mode,
            encode_colorant_family(&colorant_family),
            channel_count as i64,
            encode_json(&channel_labels)?,
            total_ink_limit_percent.map(|value| value as i64),
            black_ink_limit_percent.map(|value| value as i64),
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
        printer_manufacturer: detail
            .printer
            .as_ref()
            .map(|printer| printer.manufacturer.clone())
            .unwrap_or_default(),
        printer_model: detail
            .printer
            .as_ref()
            .map(|printer| printer.model.clone())
            .unwrap_or_default(),
        workspace_path: detail.workspace_path,
        print_path: detail.context.print_path,
        media_setting: detail.context.media_setting,
        quality_mode: detail.context.quality_mode,
        colorant_family: detail.context.colorant_family,
        channel_count: detail.context.channel_count,
        channel_labels: detail.context.channel_labels,
        total_ink_limit_percent: detail.context.total_ink_limit_percent,
        black_ink_limit_percent: detail.context.black_ink_limit_percent,
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
                new_profile_jobs.printer_paper_preset_id,
                new_profile_jobs.print_path,
                new_profile_jobs.media_setting,
                new_profile_jobs.quality_mode,
                new_profile_jobs.colorant_family_snapshot,
                new_profile_jobs.channel_count_snapshot,
                new_profile_jobs.channel_labels_snapshot,
                new_profile_jobs.total_ink_limit_percent_snapshot,
                new_profile_jobs.black_ink_limit_percent_snapshot,
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
                    row.get::<_, Option<String>>(11)?,
                    row.get::<_, String>(12)?,
                    row.get::<_, String>(13)?,
                    row.get::<_, String>(14)?,
                    row.get::<_, String>(15)?,
                    row.get::<_, i64>(16)?,
                    row.get::<_, String>(17)?,
                    row.get::<_, Option<i64>>(18)?,
                    row.get::<_, Option<i64>>(19)?,
                    row.get::<_, String>(20)?,
                    row.get::<_, String>(21)?,
                    row.get::<_, String>(22)?,
                    row.get::<_, String>(23)?,
                    row.get::<_, String>(24)?,
                    row.get::<_, i64>(25)?,
                    row.get::<_, i64>(26)?,
                    row.get::<_, i64>(27)?,
                    row.get::<_, Option<String>>(28)?,
                    row.get::<_, i64>(29)?,
                    row.get::<_, i64>(30)?,
                    row.get::<_, Option<String>>(31)?,
                    row.get::<_, Option<String>>(32)?,
                    row.get::<_, Option<String>>(33)?,
                    row.get::<_, Option<String>>(34)?,
                    row.get::<_, i64>(35)?,
                    row.get::<_, Option<String>>(36)?,
                    row.get::<_, Option<String>>(37)?,
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
        .28
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
    let channel_labels = decode_json::<Vec<String>>(&row.17);

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
            printer_paper_preset_id: row.11,
            print_path: row.12,
            media_setting: row.13,
            quality_mode: row.14,
            colorant_family: decode_colorant_family(&row.15),
            channel_count: row.16.max(1) as u32,
            channel_labels,
            total_ink_limit_percent: row.18.map(|value| value.max(1) as u32),
            black_ink_limit_percent: row.19.map(|value| value.max(1) as u32),
            print_path_notes: row.20,
            measurement_notes: row.21,
            measurement_observer: row.22,
            measurement_illuminant: row.23,
            measurement_mode: decode_measurement_mode(&row.24),
        },
        target_settings: TargetSettingsRecord {
            patch_count: row.25.max(64) as u32,
            improve_neutrals: decode_bool(row.26),
            use_existing_profile_to_help_target_planning: decode_bool(row.27),
            planning_profile_id: row.28,
            planning_profile_name,
        },
        print_settings: PrintSettingsRecord {
            print_without_color_management: decode_bool(row.29),
            drying_time_minutes: row.30.max(1) as u32,
            printed_at: row.31,
            drying_ready_at: row.32,
        },
        measurement: MeasurementStatusRecord {
            measurement_source_path: row.33,
            scan_file_path: row.34,
            has_measurement_checkpoint: decode_bool(row.35),
        },
        latest_error: row.36,
        published_profile_id: row.37,
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
        ORDER BY updated_at DESC, created_at DESC, id DESC
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

fn list_untouched_blank_new_profile_draft_candidates(
    connection: &Connection,
) -> EngineResult<Vec<UntouchedBlankDraftCandidate>> {
    let mut statement = connection.prepare(
        r#"
        SELECT
            jobs.id,
            new_profile_jobs.workspace_path
        FROM jobs
        INNER JOIN new_profile_jobs ON new_profile_jobs.id = jobs.id
        WHERE jobs.kind = 'new_profile'
          AND jobs.status IN ('draft', 'ready', 'active', 'review', 'blocked', 'failed')
          AND TRIM(new_profile_jobs.profile_name) = ''
          AND new_profile_jobs.printer_id IS NULL
          AND new_profile_jobs.paper_id IS NULL
          AND new_profile_jobs.printer_paper_preset_id IS NULL
          AND TRIM(new_profile_jobs.print_path) = ''
          AND TRIM(new_profile_jobs.media_setting) = ''
          AND TRIM(new_profile_jobs.quality_mode) = ''
          AND TRIM(new_profile_jobs.print_path_notes) = ''
          AND TRIM(new_profile_jobs.measurement_notes) = ''
          AND new_profile_jobs.measurement_source_path IS NULL
          AND new_profile_jobs.scan_file_path IS NULL
          AND new_profile_jobs.has_measurement_checkpoint = 0
          AND new_profile_jobs.printed_at IS NULL
          AND new_profile_jobs.drying_ready_at IS NULL
          AND new_profile_jobs.planning_profile_id IS NULL
          AND new_profile_jobs.published_profile_id IS NULL
          AND (new_profile_jobs.latest_error IS NULL OR TRIM(new_profile_jobs.latest_error) = '')
          AND NOT EXISTS (
              SELECT 1
              FROM artifacts
              WHERE artifacts.job_id = jobs.id
          )
          AND NOT EXISTS (
              SELECT 1
              FROM job_commands
              WHERE job_commands.job_id = jobs.id
          )
          AND NOT EXISTS (
              SELECT 1
              FROM app_settings
              WHERE app_settings.key IN (
                  'new_profile.review.' || jobs.id,
                  'new_profile.review_notes.' || jobs.id
              )
          )
        ORDER BY jobs.updated_at DESC, jobs.created_at DESC, jobs.id DESC
        "#,
    )?;

    let rows = statement.query_map([], |row| {
        Ok(UntouchedBlankDraftCandidate {
            id: row.get(0)?,
            workspace_path: row.get(1)?,
        })
    })?;

    rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
}

fn list_resumable_new_profile_job_candidates(
    connection: &Connection,
) -> EngineResult<Vec<ResumableNewProfileJobCandidate>> {
    let mut statement = connection.prepare(
        r#"
        SELECT
            jobs.id,
            new_profile_jobs.workspace_path,
            EXISTS (
                SELECT 1
                FROM job_commands
                WHERE job_commands.job_id = jobs.id
                  AND job_commands.state = 'running'
            ) AS has_running_command
        FROM jobs
        INNER JOIN new_profile_jobs ON new_profile_jobs.id = jobs.id
        WHERE jobs.kind = 'new_profile'
          AND jobs.status IN ('draft', 'ready', 'active', 'review', 'blocked', 'failed')
        ORDER BY jobs.updated_at DESC, jobs.created_at DESC, jobs.id DESC
        "#,
    )?;

    let rows = statement.query_map([], |row| {
        Ok(ResumableNewProfileJobCandidate {
            id: row.get(0)?,
            workspace_path: row.get(1)?,
            has_running_command: row.get::<_, i64>(2)? != 0,
        })
    })?;

    rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
}

fn collapse_untouched_blank_new_profile_drafts(connection: &mut Connection) -> EngineResult<()> {
    let mut deleted_workspace_paths = Vec::new();

    {
        let transaction = connection.transaction()?;
        let duplicates = list_untouched_blank_new_profile_draft_candidates(&transaction)?;
        for candidate in duplicates.into_iter().skip(1) {
            delete_new_profile_job_records(&transaction, &candidate.id)?;
            deleted_workspace_paths.push(candidate.workspace_path);
        }
        transaction.commit()?;
    }

    for workspace_path in deleted_workspace_paths {
        remove_workspace_directory(&workspace_path);
    }

    Ok(())
}

fn delete_new_profile_job_records(connection: &Connection, job_id: &str) -> EngineResult<()> {
    let review_key = format!("new_profile.review.{job_id}");
    let review_notes_key = format!("new_profile.review_notes.{job_id}");
    connection.execute(
        "DELETE FROM app_settings WHERE key IN (?1, ?2)",
        params![review_key, review_notes_key],
    )?;

    let deleted = connection.execute("DELETE FROM jobs WHERE id = ?1", params![job_id])?;
    if deleted == 0 {
        return Err(format!("New Profile job {job_id} was not found.").into());
    }

    Ok(())
}

fn load_printers(connection: &Connection) -> EngineResult<Vec<PrinterRecord>> {
    let mut statement = connection.prepare(
        r#"
        SELECT
            id,
            manufacturer,
            model,
            nickname,
            transport_style,
            colorant_family,
            channel_count,
            channel_labels,
            supported_media_settings,
            supported_quality_modes,
            monochrome_path_notes,
            notes,
            created_at,
            updated_at
        FROM printers
        ORDER BY COALESCE(NULLIF(nickname, ''), TRIM(manufacturer || ' ' || model), model), updated_at DESC
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
            manufacturer,
            paper_line,
            surface_class,
            basis_weight_value,
            basis_weight_unit,
            thickness_value,
            thickness_unit,
            surface_texture,
            base_material,
            media_color,
            opacity,
            whiteness,
            oba_content,
            ink_compatibility,
            notes,
            created_at,
            updated_at
        FROM papers
        ORDER BY manufacturer, paper_line, updated_at DESC
        "#,
    )?;

    let rows = statement.query_map([], map_paper_row)?;
    rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
}

fn load_printer_paper_presets(
    connection: &Connection,
) -> EngineResult<Vec<PrinterPaperPresetRecord>> {
    let mut statement = connection.prepare(
        r#"
        SELECT
            id,
            printer_id,
            paper_id,
            label,
            print_path,
            media_setting,
            quality_mode,
            total_ink_limit_percent,
            black_ink_limit_percent,
            notes,
            created_at,
            updated_at
        FROM printer_paper_presets
        ORDER BY printer_id, paper_id, label, print_path, media_setting, quality_mode
        "#,
    )?;

    let rows = statement.query_map([], map_printer_paper_preset_row)?;
    rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
}

fn load_printer(connection: &Connection, printer_id: &str) -> EngineResult<Option<PrinterRecord>> {
    connection
        .query_row(
            r#"
            SELECT
                id,
                manufacturer,
                model,
                nickname,
                transport_style,
                colorant_family,
                channel_count,
                channel_labels,
                supported_media_settings,
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

fn load_printer_paper_preset(
    connection: &Connection,
    preset_id: &str,
) -> EngineResult<Option<PrinterPaperPresetRecord>> {
    connection
        .query_row(
            r#"
            SELECT
                id,
                printer_id,
                paper_id,
                label,
                print_path,
                media_setting,
                quality_mode,
                total_ink_limit_percent,
                black_ink_limit_percent,
                notes,
                created_at,
                updated_at
            FROM printer_paper_presets
            WHERE id = ?1
            "#,
            params![preset_id],
            map_printer_paper_preset_row,
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
                manufacturer,
                paper_line,
                surface_class,
                basis_weight_value,
                basis_weight_unit,
                thickness_value,
                thickness_unit,
                surface_texture,
                base_material,
                media_color,
                opacity,
                whiteness,
                oba_content,
                ink_compatibility,
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
    let manufacturer: String = row.get(1)?;
    let model: String = row.get(2)?;
    let nickname: String = row.get(3)?;
    let channel_labels_json: String = row.get(7)?;
    let supported_media_settings_json: String = row.get(8)?;
    let supported_quality_modes_json: String = row.get(9)?;

    Ok(PrinterRecord {
        id: row.get(0)?,
        manufacturer: manufacturer.clone(),
        model: model.clone(),
        nickname: nickname.clone(),
        transport_style: row.get(4)?,
        colorant_family: decode_colorant_family(&row.get::<_, String>(5)?),
        channel_count: row.get::<_, i64>(6)? as u32,
        channel_labels: decode_json(&channel_labels_json),
        supported_media_settings: decode_json(&supported_media_settings_json),
        supported_quality_modes: decode_json(&supported_quality_modes_json),
        monochrome_path_notes: row.get(10)?,
        notes: row.get(11)?,
        display_name: display_printer_name(&manufacturer, &model, &nickname),
        created_at: row.get(12)?,
        updated_at: row.get(13)?,
    })
}

fn map_paper_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<PaperRecord> {
    let manufacturer: String = row.get(1)?;
    let paper_line: String = row.get(2)?;
    let surface_class: String = row.get(3)?;

    Ok(PaperRecord {
        id: row.get(0)?,
        manufacturer: manufacturer.clone(),
        paper_line: paper_line.clone(),
        surface_class: surface_class.clone(),
        basis_weight_value: row.get(4)?,
        basis_weight_unit: decode_paper_weight_unit(&row.get::<_, String>(5)?),
        thickness_value: row.get(6)?,
        thickness_unit: decode_paper_thickness_unit(&row.get::<_, String>(7)?),
        surface_texture: row.get(8)?,
        base_material: row.get(9)?,
        media_color: row.get(10)?,
        opacity: row.get(11)?,
        whiteness: row.get(12)?,
        oba_content: row.get(13)?,
        ink_compatibility: row.get(14)?,
        notes: row.get(15)?,
        display_name: display_paper_name(&manufacturer, &paper_line, &surface_class),
        created_at: row.get(16)?,
        updated_at: row.get(17)?,
    })
}

fn map_printer_paper_preset_row(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<PrinterPaperPresetRecord> {
    let label: String = row.get(3)?;
    let print_path: String = row.get(4)?;
    let media_setting: String = row.get(5)?;
    let quality_mode: String = row.get(6)?;

    Ok(PrinterPaperPresetRecord {
        id: row.get(0)?,
        printer_id: row.get(1)?,
        paper_id: row.get(2)?,
        label: label.clone(),
        print_path: print_path.clone(),
        media_setting: media_setting.clone(),
        quality_mode: quality_mode.clone(),
        total_ink_limit_percent: row.get::<_, Option<i64>>(7)?.map(|value| value as u32),
        black_ink_limit_percent: row.get::<_, Option<i64>>(8)?.map(|value| value as u32),
        notes: row.get(9)?,
        display_name: display_printer_paper_preset_name(
            &label,
            &print_path,
            &media_setting,
            &quality_mode,
        ),
        created_at: row.get(10)?,
        updated_at: row.get(11)?,
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

fn load_printer_profile(
    connection: &Connection,
    profile_id: &str,
) -> EngineResult<Option<PrinterProfileRecord>> {
    connection
        .query_row(
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
            WHERE id = ?1
            "#,
            params![profile_id],
            |row| {
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
            },
        )
        .optional()
        .map_err(Into::into)
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
    let has_context = !profile_name.is_empty()
        && detail.printer.is_some()
        && detail.paper.is_some()
        && !detail.context.media_setting.trim().is_empty()
        && !detail.context.quality_mode.trim().is_empty();
    let next_action = if has_context {
        "Generate target files"
    } else {
        "Select printer and paper settings"
    };
    let stage = if !has_context {
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
    if detail.context.media_setting.trim().is_empty() {
        return Err("Choose the printer and paper settings before generating target files.".into());
    }
    if detail.context.quality_mode.trim().is_empty() {
        return Err("Choose the printer and paper settings before generating target files.".into());
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

fn remove_workspace_directory(workspace_path: &str) {
    let workspace_path = Path::new(workspace_path);
    if workspace_path.exists() {
        let _ = std::fs::remove_dir_all(workspace_path);
    }
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
            manufacturer TEXT NOT NULL DEFAULT '',
            model TEXT NOT NULL,
            nickname TEXT NOT NULL DEFAULT '',
            transport_style TEXT NOT NULL DEFAULT '',
            colorant_family TEXT NOT NULL DEFAULT 'cmyk',
            channel_count INTEGER NOT NULL DEFAULT 4,
            channel_labels TEXT NOT NULL DEFAULT '[]',
            supported_media_settings TEXT NOT NULL DEFAULT '[]',
            supported_quality_modes TEXT NOT NULL DEFAULT '[]',
            monochrome_path_notes TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS papers (
            id TEXT PRIMARY KEY,
            manufacturer TEXT NOT NULL DEFAULT '',
            paper_line TEXT NOT NULL DEFAULT '',
            surface_class TEXT NOT NULL DEFAULT '',
            basis_weight_value TEXT NOT NULL DEFAULT '',
            basis_weight_unit TEXT NOT NULL DEFAULT '',
            thickness_value TEXT NOT NULL DEFAULT '',
            thickness_unit TEXT NOT NULL DEFAULT '',
            surface_texture TEXT NOT NULL DEFAULT '',
            base_material TEXT NOT NULL DEFAULT '',
            media_color TEXT NOT NULL DEFAULT '',
            opacity TEXT NOT NULL DEFAULT '',
            whiteness TEXT NOT NULL DEFAULT '',
            oba_content TEXT NOT NULL DEFAULT '',
            ink_compatibility TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS printer_paper_presets (
            id TEXT PRIMARY KEY,
            printer_id TEXT NOT NULL REFERENCES printers(id),
            paper_id TEXT NOT NULL REFERENCES papers(id),
            label TEXT NOT NULL DEFAULT '',
            print_path TEXT NOT NULL DEFAULT '',
            media_setting TEXT NOT NULL,
            quality_mode TEXT NOT NULL,
            total_ink_limit_percent INTEGER,
            black_ink_limit_percent INTEGER,
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
            printer_paper_preset_id TEXT REFERENCES printer_paper_presets(id),
            print_path TEXT NOT NULL DEFAULT '',
            media_setting TEXT NOT NULL DEFAULT '',
            quality_mode TEXT NOT NULL DEFAULT '',
            colorant_family_snapshot TEXT NOT NULL DEFAULT 'cmyk',
            channel_count_snapshot INTEGER NOT NULL DEFAULT 4,
            channel_labels_snapshot TEXT NOT NULL DEFAULT '[]',
            total_ink_limit_percent_snapshot INTEGER,
            black_ink_limit_percent_snapshot INTEGER,
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
    ensure_column(
        connection,
        "printers",
        "manufacturer",
        "TEXT NOT NULL DEFAULT ''",
    )?;
    ensure_column(connection, "printers", "model", "TEXT NOT NULL DEFAULT ''")?;
    ensure_column(
        connection,
        "printers",
        "colorant_family",
        "TEXT NOT NULL DEFAULT 'cmyk'",
    )?;
    ensure_column(
        connection,
        "printers",
        "channel_count",
        "INTEGER NOT NULL DEFAULT 4",
    )?;
    ensure_column(
        connection,
        "printers",
        "channel_labels",
        "TEXT NOT NULL DEFAULT '[]'",
    )?;
    ensure_column(
        connection,
        "printers",
        "supported_media_settings",
        "TEXT NOT NULL DEFAULT '[]'",
    )?;
    ensure_column(
        connection,
        "printers",
        "supported_quality_modes",
        "TEXT NOT NULL DEFAULT '[]'",
    )?;
    ensure_column(
        connection,
        "papers",
        "manufacturer",
        "TEXT NOT NULL DEFAULT ''",
    )?;
    ensure_column(
        connection,
        "papers",
        "paper_line",
        "TEXT NOT NULL DEFAULT ''",
    )?;
    ensure_column(
        connection,
        "papers",
        "basis_weight_value",
        "TEXT NOT NULL DEFAULT ''",
    )?;
    ensure_column(
        connection,
        "papers",
        "basis_weight_unit",
        "TEXT NOT NULL DEFAULT ''",
    )?;
    ensure_column(
        connection,
        "papers",
        "thickness_value",
        "TEXT NOT NULL DEFAULT ''",
    )?;
    ensure_column(
        connection,
        "papers",
        "thickness_unit",
        "TEXT NOT NULL DEFAULT ''",
    )?;
    ensure_column(
        connection,
        "papers",
        "surface_texture",
        "TEXT NOT NULL DEFAULT ''",
    )?;
    ensure_column(
        connection,
        "papers",
        "base_material",
        "TEXT NOT NULL DEFAULT ''",
    )?;
    ensure_column(
        connection,
        "papers",
        "media_color",
        "TEXT NOT NULL DEFAULT ''",
    )?;
    ensure_column(connection, "papers", "opacity", "TEXT NOT NULL DEFAULT ''")?;
    ensure_column(
        connection,
        "papers",
        "whiteness",
        "TEXT NOT NULL DEFAULT ''",
    )?;
    ensure_column(
        connection,
        "papers",
        "oba_content",
        "TEXT NOT NULL DEFAULT ''",
    )?;
    ensure_column(
        connection,
        "papers",
        "ink_compatibility",
        "TEXT NOT NULL DEFAULT ''",
    )?;
    ensure_column(
        connection,
        "printer_paper_presets",
        "print_path",
        "TEXT NOT NULL DEFAULT ''",
    )?;
    ensure_column(
        connection,
        "new_profile_jobs",
        "printer_paper_preset_id",
        "TEXT",
    )?;
    ensure_column(
        connection,
        "new_profile_jobs",
        "print_path",
        "TEXT NOT NULL DEFAULT ''",
    )?;
    ensure_column(
        connection,
        "new_profile_jobs",
        "colorant_family_snapshot",
        "TEXT NOT NULL DEFAULT 'cmyk'",
    )?;
    ensure_column(
        connection,
        "new_profile_jobs",
        "channel_count_snapshot",
        "INTEGER NOT NULL DEFAULT 4",
    )?;
    ensure_column(
        connection,
        "new_profile_jobs",
        "channel_labels_snapshot",
        "TEXT NOT NULL DEFAULT '[]'",
    )?;
    ensure_column(
        connection,
        "new_profile_jobs",
        "total_ink_limit_percent_snapshot",
        "INTEGER",
    )?;
    ensure_column(
        connection,
        "new_profile_jobs",
        "black_ink_limit_percent_snapshot",
        "INTEGER",
    )?;

    Ok(())
}

fn upgrade_legacy_jobs(connection: &Connection, app_support_path: &str) -> EngineResult<()> {
    if table_has_column(connection, "printers", "make_model")? {
        connection.execute(
            r#"
            UPDATE printers
            SET
                model = CASE
                    WHEN COALESCE(NULLIF(model, ''), '') = '' THEN COALESCE(make_model, '')
                    ELSE model
                END,
                manufacturer = COALESCE(manufacturer, '')
            "#,
            [],
        )?;
    }

    if table_has_column(connection, "papers", "vendor_product_name")? {
        connection.execute(
            r#"
            UPDATE papers
            SET
                paper_line = CASE
                    WHEN COALESCE(NULLIF(paper_line, ''), '') = '' THEN COALESCE(vendor_product_name, '')
                    ELSE paper_line
                END
            "#,
            [],
        )?;
    }

    if table_has_column(connection, "papers", "vendor")? {
        connection.execute(
            r#"
            UPDATE papers
            SET
                manufacturer = CASE
                    WHEN COALESCE(NULLIF(manufacturer, ''), '') = '' THEN COALESCE(vendor, '')
                    ELSE manufacturer
                END
            "#,
            [],
        )?;
    }

    if table_has_column(connection, "papers", "product_name")? {
        connection.execute(
            r#"
            UPDATE papers
            SET
                paper_line = CASE
                    WHEN COALESCE(NULLIF(paper_line, ''), '') = '' THEN COALESCE(product_name, '')
                    ELSE paper_line
                END
            "#,
            [],
        )?;
    }

    if table_has_column(connection, "papers", "oba_fluorescence_notes")? {
        connection.execute(
            r#"
            UPDATE papers
            SET
                oba_content = CASE
                    WHEN COALESCE(NULLIF(oba_content, ''), '') = '' THEN COALESCE(oba_fluorescence_notes, '')
                    ELSE oba_content
                END
            "#,
            [],
        )?;
    }

    if table_has_column(connection, "papers", "weight_thickness")? {
        connection.execute(
            r#"
            UPDATE papers
            SET
                notes = CASE
                    WHEN COALESCE(NULLIF(weight_thickness, ''), '') = '' THEN COALESCE(notes, '')
                    WHEN COALESCE(NULLIF(basis_weight_value, ''), '') <> '' OR COALESCE(NULLIF(thickness_value, ''), '') <> '' THEN COALESCE(notes, '')
                    WHEN instr(COALESCE(notes, ''), 'Legacy weight/thickness: ') > 0 THEN notes
                    WHEN COALESCE(NULLIF(notes, ''), '') = '' THEN 'Legacy weight/thickness: ' || weight_thickness
                    ELSE notes || char(10) || char(10) || 'Legacy weight/thickness: ' || weight_thickness
                END
            "#,
            [],
        )?;
    }

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
            printer_paper_preset_id,
            print_path,
            media_setting,
            quality_mode,
            colorant_family_snapshot,
            channel_count_snapshot,
            channel_labels_snapshot,
            total_ink_limit_percent_snapshot,
            black_ink_limit_percent_snapshot,
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
            VALUES (?1, ?2, ?3, NULL, NULL, NULL, '', '', '', 'cmyk', 4, '[]', NULL, NULL, '', '', '1931_2', 'D50', 'strip', 836, 0, 0, NULL, 1, 120, NULL, NULL, NULL, NULL, 0, NULL, NULL, ?4, ?5)
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

    connection.execute(
        r#"
        UPDATE new_profile_jobs
        SET
            colorant_family_snapshot = COALESCE(NULLIF(colorant_family_snapshot, ''), 'cmyk'),
            channel_count_snapshot = CASE
                WHEN channel_count_snapshot IS NULL OR channel_count_snapshot <= 0 THEN 4
                ELSE channel_count_snapshot
            END,
            channel_labels_snapshot = COALESCE(NULLIF(channel_labels_snapshot, ''), '[]')
        "#,
        [],
    )?;

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

fn encode_colorant_family(value: &ColorantFamily) -> &'static str {
    match value {
        ColorantFamily::GrayK => "gray_k",
        ColorantFamily::Rgb => "rgb",
        ColorantFamily::Cmy => "cmy",
        ColorantFamily::Cmyk => "cmyk",
        ColorantFamily::ExtendedN => "extended_n",
    }
}

fn decode_colorant_family(value: &str) -> ColorantFamily {
    match value {
        "gray_k" => ColorantFamily::GrayK,
        "rgb" => ColorantFamily::Rgb,
        "cmy" => ColorantFamily::Cmy,
        "extended_n" => ColorantFamily::ExtendedN,
        _ => ColorantFamily::Cmyk,
    }
}

fn encode_paper_weight_unit(value: &PaperWeightUnit) -> &'static str {
    match value {
        PaperWeightUnit::Unspecified => "",
        PaperWeightUnit::Gsm => "gsm",
        PaperWeightUnit::Lb => "lb",
    }
}

fn decode_paper_weight_unit(value: &str) -> PaperWeightUnit {
    match value {
        "gsm" => PaperWeightUnit::Gsm,
        "lb" => PaperWeightUnit::Lb,
        _ => PaperWeightUnit::Unspecified,
    }
}

fn encode_paper_thickness_unit(value: &PaperThicknessUnit) -> &'static str {
    match value {
        PaperThicknessUnit::Unspecified => "",
        PaperThicknessUnit::Mil => "mil",
        PaperThicknessUnit::Mm => "mm",
        PaperThicknessUnit::Micron => "micron",
    }
}

fn decode_paper_thickness_unit(value: &str) -> PaperThicknessUnit {
    match value {
        "mil" => PaperThicknessUnit::Mil,
        "mm" => PaperThicknessUnit::Mm,
        "micron" => PaperThicknessUnit::Micron,
        _ => PaperThicknessUnit::Unspecified,
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

fn display_printer_name(manufacturer: &str, model: &str, nickname: &str) -> String {
    let manufacturer = trim(manufacturer);
    let model = trim(model);
    let nickname = trim(nickname);
    if nickname.is_empty() {
        if manufacturer.is_empty() {
            model
        } else if model.is_empty() {
            manufacturer
        } else {
            format!("{manufacturer} {model}")
        }
    } else {
        nickname
    }
}

fn display_paper_name(manufacturer: &str, paper_line: &str, surface_class: &str) -> String {
    let manufacturer = trim(manufacturer);
    let paper_line = trim(paper_line);
    let surface_class = trim(surface_class);
    let base = if manufacturer.is_empty() {
        paper_line
    } else if paper_line.is_empty() {
        manufacturer
    } else {
        format!("{manufacturer} {paper_line}")
    };

    if surface_class.is_empty() {
        base
    } else {
        format!("{base} ({surface_class})")
    }
}

fn display_printer_paper_preset_name(
    label: &str,
    print_path: &str,
    media_setting: &str,
    quality_mode: &str,
) -> String {
    let label = trim(label);
    if !label.is_empty() {
        return label;
    }

    let print_path = trim(print_path);
    let media_setting = trim(media_setting);
    let quality_mode = trim(quality_mode);

    let mut parts = Vec::new();
    if !print_path.is_empty() {
        parts.push(print_path);
    }
    if !media_setting.is_empty() {
        parts.push(media_setting);
    }
    if !quality_mode.is_empty() {
        parts.push(quality_mode);
    }

    if parts.is_empty() {
        "Printer and paper settings".to_string()
    } else {
        parts.join(" | ")
    }
}

fn validate_printer_identity(manufacturer: &str, model: &str) -> EngineResult<()> {
    if manufacturer.trim().is_empty() || model.trim().is_empty() {
        return Err("Enter both a printer manufacturer and model.".into());
    }
    Ok(())
}

fn validate_paper_identity(paper_line: &str) -> EngineResult<()> {
    if paper_line.trim().is_empty() {
        return Err("Enter a paper line or make.".into());
    }
    Ok(())
}

fn normalized_catalog_values(values: Vec<String>) -> Vec<String> {
    let mut normalized = Vec::new();
    for value in trimmed_strings(values) {
        if !normalized.contains(&value) {
            normalized.push(value);
        }
    }
    normalized
}

fn normalize_channel_configuration(
    family: &ColorantFamily,
    requested_channel_count: u32,
    requested_labels: Vec<String>,
) -> EngineResult<(u32, Vec<String>)> {
    let normalized_labels = normalized_catalog_values(requested_labels);
    match family {
        ColorantFamily::GrayK => Ok((1, Vec::new())),
        ColorantFamily::Rgb | ColorantFamily::Cmy => Ok((3, Vec::new())),
        ColorantFamily::Cmyk => Ok((4, Vec::new())),
        ColorantFamily::ExtendedN => {
            if !(6..=15).contains(&requested_channel_count) {
                return Err("Extended N-color printers must use between 6 and 15 channels.".into());
            }
            if !normalized_labels.is_empty()
                && normalized_labels.len() != requested_channel_count as usize
            {
                return Err("Extended N-color channel labels must match the channel count.".into());
            }
            Ok((requested_channel_count, normalized_labels))
        }
    }
}

fn validate_context_catalog_selection(
    printer: &PrinterRecord,
    media_setting: &str,
    quality_mode: &str,
) -> EngineResult<()> {
    if !media_setting.trim().is_empty()
        && !printer.supported_media_settings.is_empty()
        && !printer
            .supported_media_settings
            .iter()
            .any(|item| item == media_setting)
    {
        return Err("Choose a media setting that belongs to this printer.".into());
    }
    if !quality_mode.trim().is_empty()
        && !printer.supported_quality_modes.is_empty()
        && !printer
            .supported_quality_modes
            .iter()
            .any(|item| item == quality_mode)
    {
        return Err("Choose a quality mode that belongs to this printer.".into());
    }
    Ok(())
}

#[derive(Debug, Clone)]
struct ValidatedPrinterPaperPreset {
    media_setting: String,
    quality_mode: String,
    total_ink_limit_percent: Option<u32>,
    black_ink_limit_percent: Option<u32>,
}

fn validate_printer_paper_preset(
    printer: &PrinterRecord,
    media_setting: String,
    quality_mode: String,
    total_ink_limit_percent: Option<u32>,
    black_ink_limit_percent: Option<u32>,
) -> EngineResult<ValidatedPrinterPaperPreset> {
    if media_setting.is_empty() {
        return Err("Choose a media setting before saving printer and paper settings.".into());
    }
    if quality_mode.is_empty() {
        return Err("Choose a quality mode before saving printer and paper settings.".into());
    }
    if printer.supported_media_settings.is_empty()
        || !printer
            .supported_media_settings
            .iter()
            .any(|item| item == &media_setting)
    {
        return Err("Choose a media setting from this printer's saved media settings.".into());
    }
    if printer.supported_quality_modes.is_empty()
        || !printer
            .supported_quality_modes
            .iter()
            .any(|item| item == &quality_mode)
    {
        return Err("Choose a quality mode from this printer's saved quality modes.".into());
    }
    let total_ink_limit_percent =
        validate_percent_limit(total_ink_limit_percent, 400, "total ink limit")?;
    let black_ink_limit_percent =
        validate_percent_limit(black_ink_limit_percent, 100, "black ink limit")?;
    if black_ink_limit_percent.is_some() && !printer_has_black_channel(printer) {
        return Err(
            "Black ink limit is only available when the printer setup includes a black channel."
                .into(),
        );
    }

    Ok(ValidatedPrinterPaperPreset {
        media_setting,
        quality_mode,
        total_ink_limit_percent,
        black_ink_limit_percent,
    })
}

fn validate_percent_limit(value: Option<u32>, max: u32, label: &str) -> EngineResult<Option<u32>> {
    match value {
        Some(value) if value == 0 || value > max => {
            Err(format!("Choose a valid {label} between 1 and {max}%.").into())
        }
        Some(value) => Ok(Some(value)),
        None => Ok(None),
    }
}

fn printer_has_black_channel(printer: &PrinterRecord) -> bool {
    colorant_family_has_black_channel(&printer.colorant_family, &printer.channel_labels)
}

fn colorant_family_has_black_channel(family: &ColorantFamily, channel_labels: &[String]) -> bool {
    match family {
        ColorantFamily::GrayK | ColorantFamily::Cmyk => true,
        ColorantFamily::ExtendedN => channel_labels.iter().any(|label| {
            let lowered = label.trim().to_ascii_lowercase();
            lowered == "k" || lowered == "black"
        }),
        ColorantFamily::Rgb | ColorantFamily::Cmy => false,
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
    use crate::model::{
        DiagnosticCategory, DiagnosticEventFilter, DiagnosticEventInput, DiagnosticLevel,
        DiagnosticPrivacy, InstrumentConnectionState, PaperThicknessUnit, PaperWeightUnit,
        SaveNewProfileContextInput,
    };
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

    fn sample_paper_input() -> CreatePaperInput {
        CreatePaperInput {
            manufacturer: "Canson".to_string(),
            paper_line: "Rag".to_string(),
            surface_class: "Matte".to_string(),
            basis_weight_value: "310".to_string(),
            basis_weight_unit: PaperWeightUnit::Gsm,
            thickness_value: String::new(),
            thickness_unit: PaperThicknessUnit::Unspecified,
            surface_texture: "Smooth".to_string(),
            base_material: "Cotton rag".to_string(),
            media_color: "White".to_string(),
            opacity: "98%".to_string(),
            whiteness: "89".to_string(),
            oba_content: "Low OBA".to_string(),
            ink_compatibility: "Pigment".to_string(),
            notes: String::new(),
        }
    }

    fn sample_printer_input() -> CreatePrinterInput {
        CreatePrinterInput {
            manufacturer: "Epson".to_string(),
            model: "P900".to_string(),
            nickname: "P900".to_string(),
            transport_style: "Sheet-fed".to_string(),
            colorant_family: ColorantFamily::Cmyk,
            channel_count: 4,
            channel_labels: Vec::new(),
            supported_media_settings: vec!["Premium Luster".to_string()],
            supported_quality_modes: vec!["1440 dpi".to_string()],
            monochrome_path_notes: "".to_string(),
            notes: "".to_string(),
        }
    }

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
    fn diagnostic_filters_are_applied_before_limit() {
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
                VALUES (?1, ?2, 'error', 'cli', 'engine.cli', 'Older matching needle event',
                    '{"summary":"needle"}', 'public', 'job-match', NULL, NULL, NULL, NULL, NULL, NULL)
                "#,
                params!["diag-match", "2026-04-20T00:00:00Z"],
            )
            .unwrap();

        for (id, timestamp) in [
            ("diag-newer-1", "2026-04-20T00:00:03Z"),
            ("diag-newer-2", "2026-04-20T00:00:02Z"),
            ("diag-newer-3", "2026-04-20T00:00:01Z"),
        ] {
            connection
                .execute(
                    r#"
                    INSERT INTO diagnostic_events (
                        id, timestamp, level, category, source, message, details_json, privacy,
                        job_id, command_id, profile_id, issue_case_id, duration_ms, operation_id, parent_operation_id
                    )
                    VALUES (?1, ?2, 'info', 'engine', 'engine.test', 'Newer non-matching event',
                        '{}', 'public', 'job-other', NULL, NULL, NULL, NULL, NULL, NULL)
                    "#,
                    params![id, timestamp],
                )
                .unwrap();
        }

        let events = list_diagnostic_events(
            &config.database_path,
            &DiagnosticEventFilter {
                levels: vec![DiagnosticLevel::Error],
                categories: vec![DiagnosticCategory::Cli],
                search_text: Some("needle".to_string()),
                job_id: Some("job-match".to_string()),
                profile_id: None,
                since_timestamp: None,
                until_timestamp: None,
                errors_only: false,
                limit: 1,
            },
        )
        .unwrap();

        assert_eq!(events.len(), 1);
        assert_eq!(events[0].id, "diag-match");
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

        let summary =
            get_diagnostics_summary(&config.database_path, "Ready", "3.5.0", "system_toolchain")
                .unwrap();

        assert_eq!(summary.total_count, 4);
        assert_eq!(summary.warning_count, 1);
        assert_eq!(summary.error_count, 1);
        assert_eq!(summary.critical_count, 1);
        assert_eq!(
            summary.latest_critical_message.as_deref(),
            Some("Diagnostics unavailable")
        );
        assert_eq!(summary.argyll_version, "3.5.0");
    }

    #[test]
    fn diagnostic_retention_prunes_events_older_than_retention_window() {
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

    #[test]
    fn dashboard_snapshot_returns_persisted_jobs() {
        let temp = tempdir().unwrap();
        let config = build_config(temp.path());
        std::fs::create_dir_all(temp.path().join("app-support")).unwrap();

        initialize_database(&config).unwrap();
        let printer = create_printer(
            &config.database_path,
            &CreatePrinterInput {
                manufacturer: "Epson".to_string(),
                model: "P900".to_string(),
                nickname: "P900".to_string(),
                transport_style: "Sheet-fed".to_string(),
                colorant_family: ColorantFamily::Cmyk,
                channel_count: 4,
                channel_labels: Vec::new(),
                supported_media_settings: vec!["Premium Luster".to_string()],
                supported_quality_modes: vec!["1440 dpi".to_string()],
                monochrome_path_notes: "".to_string(),
                notes: "".to_string(),
            },
        )
        .unwrap();
        let paper = create_paper(
            &config.database_path,
            &CreatePaperInput {
                notes: "".to_string(),
                ..sample_paper_input()
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
                printer_paper_preset_id: None,
                print_path: "Canon driver".to_string(),
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

        let review_json = encode_json(&ReviewSummaryRecord {
            result: "Pass".to_string(),
            verified_against_file: "/tmp/review.ti3".to_string(),
            print_settings: "Premium Luster / 1440 dpi".to_string(),
            last_verification_date: Some("2026-04-20T12:00:00Z".to_string()),
            average_de00: Some(1.2),
            maximum_de00: Some(2.8),
            notes: "Good first build.".to_string(),
        })
        .unwrap();
        let connection = open_connection(&config.database_path).unwrap();
        connection
            .execute(
                r#"
                INSERT INTO app_settings (key, value, updated_at)
                VALUES (?1, ?2, ?3)
                "#,
                params![
                    format!("new_profile.review.{}", job.id),
                    &review_json,
                    iso_timestamp()
                ],
            )
            .unwrap();
        connection
            .execute(
                r#"
                INSERT INTO app_settings (key, value, updated_at)
                VALUES (?1, ?2, ?3)
                "#,
                params![
                    format!("new_profile.review_notes.{}", job.id),
                    "Warm up the instrument.",
                    iso_timestamp()
                ],
            )
            .unwrap();
        upsert_job_artifact(
            &config.database_path,
            &job.id,
            WorkflowStage::Context,
            ArtifactKind::Working,
            "Context Notes",
            Some("/tmp/context.txt"),
            "ready",
        )
        .unwrap();
        let command_id = insert_job_command(
            &config.database_path,
            &job.id,
            WorkflowStage::Context,
            "Generate Target",
            &["targen".to_string(), "-v".to_string()],
        )
        .unwrap();
        append_job_command_event(
            &config.database_path,
            &command_id,
            CommandStream::System,
            1,
            "Command queued.",
        )
        .unwrap();
        finish_job_command(&config.database_path, &command_id, true, Some(0)).unwrap();

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
        let artifacts_count: i64 = connection
            .query_row("SELECT COUNT(*) FROM artifacts", [], |row| row.get(0))
            .unwrap();
        let commands_count: i64 = connection
            .query_row("SELECT COUNT(*) FROM job_commands", [], |row| row.get(0))
            .unwrap();
        let command_events_count: i64 = connection
            .query_row("SELECT COUNT(*) FROM job_command_events", [], |row| {
                row.get(0)
            })
            .unwrap();
        let review_settings_count: i64 = connection
            .query_row(
                "SELECT COUNT(*) FROM app_settings WHERE key IN (?1, ?2)",
                params![
                    format!("new_profile.review.{}", job.id),
                    format!("new_profile.review_notes.{}", job.id)
                ],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(jobs_count, 0);
        assert_eq!(new_profile_jobs_count, 0);
        assert_eq!(artifacts_count, 0);
        assert_eq!(commands_count, 0);
        assert_eq!(command_events_count, 0);
        assert_eq!(review_settings_count, 0);
    }

    #[test]
    fn resolve_new_profile_launch_collapses_duplicate_blank_drafts() {
        let temp = tempdir().unwrap();
        let config = build_config(temp.path());
        std::fs::create_dir_all(temp.path().join("app-support")).unwrap();

        initialize_database(&config).unwrap();

        let first = create_new_profile_draft(
            &config.database_path,
            &config.app_support_path,
            &CreateNewProfileDraftInput {
                profile_name: None,
                printer_id: None,
                paper_id: None,
            },
        )
        .unwrap();
        std::thread::sleep(std::time::Duration::from_millis(2));
        let second = create_new_profile_draft(
            &config.database_path,
            &config.app_support_path,
            &CreateNewProfileDraftInput {
                profile_name: None,
                printer_id: None,
                paper_id: None,
            },
        )
        .unwrap();

        let resolved = resolve_new_profile_launch(
            &config.database_path,
            &config.app_support_path,
            &CreateNewProfileDraftInput {
                profile_name: None,
                printer_id: None,
                paper_id: None,
            },
        )
        .unwrap();

        assert_eq!(resolved.id, second.id);
        assert!(!Path::new(&first.workspace_path).exists());
        assert!(Path::new(&second.workspace_path).exists());

        let snapshot = load_dashboard_snapshot(&config.database_path).unwrap();
        assert_eq!(snapshot.active_work_items.len(), 1);
        assert_eq!(snapshot.active_work_items[0].id, second.id);

        let connection = open_connection(&config.database_path).unwrap();
        let jobs_count: i64 = connection
            .query_row("SELECT COUNT(*) FROM jobs", [], |row| row.get(0))
            .unwrap();
        assert_eq!(jobs_count, 1);
    }

    #[test]
    fn resolve_new_profile_launch_keeps_only_latest_resumable_job() {
        let temp = tempdir().unwrap();
        let config = build_config(temp.path());
        std::fs::create_dir_all(temp.path().join("app-support")).unwrap();

        initialize_database(&config).unwrap();
        let printer = create_printer(&config.database_path, &sample_printer_input()).unwrap();
        let paper = create_paper(&config.database_path, &sample_paper_input()).unwrap();

        let first = create_new_profile_draft(
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
                job_id: first.id.clone(),
                profile_name: "P900 Rag v1".to_string(),
                printer_id: Some(printer.id.clone()),
                paper_id: Some(paper.id.clone()),
                printer_paper_preset_id: None,
                print_path: "Canon driver".to_string(),
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

        std::thread::sleep(std::time::Duration::from_millis(2));

        let second = create_new_profile_draft(
            &config.database_path,
            &config.app_support_path,
            &CreateNewProfileDraftInput {
                profile_name: Some("P900 Rag v2".to_string()),
                printer_id: Some(printer.id.clone()),
                paper_id: Some(paper.id.clone()),
            },
        )
        .unwrap();
        save_new_profile_context(
            &config.database_path,
            &SaveNewProfileContextInput {
                job_id: second.id.clone(),
                profile_name: "P900 Rag v2".to_string(),
                printer_id: Some(printer.id.clone()),
                paper_id: Some(paper.id.clone()),
                printer_paper_preset_id: None,
                print_path: "Canon driver".to_string(),
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

        let resolved = resolve_new_profile_launch(
            &config.database_path,
            &config.app_support_path,
            &CreateNewProfileDraftInput {
                profile_name: None,
                printer_id: None,
                paper_id: None,
            },
        )
        .unwrap();

        assert_eq!(resolved.id, second.id);
        assert!(!Path::new(&first.workspace_path).exists());
        assert!(Path::new(&second.workspace_path).exists());

        let snapshot = load_dashboard_snapshot(&config.database_path).unwrap();
        assert_eq!(snapshot.active_work_items.len(), 1);
        assert_eq!(snapshot.active_work_items[0].id, second.id);
    }

    #[test]
    fn delete_printer_profile_reopens_source_job_and_clears_profile_refs() {
        let temp = tempdir().unwrap();
        let config = build_config(temp.path());
        std::fs::create_dir_all(temp.path().join("app-support")).unwrap();

        initialize_database(&config).unwrap();
        let printer = create_printer(&config.database_path, &sample_printer_input()).unwrap();
        let paper = create_paper(
            &config.database_path,
            &CreatePaperInput {
                notes: "".to_string(),
                ..sample_paper_input()
            },
        )
        .unwrap();

        let source_job = create_new_profile_draft(
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
                job_id: source_job.id.clone(),
                profile_name: "P900 Rag v1".to_string(),
                printer_id: Some(printer.id.clone()),
                paper_id: Some(paper.id.clone()),
                printer_paper_preset_id: None,
                print_path: "Canon driver".to_string(),
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
        complete_measurement(
            &config.database_path,
            &source_job.id,
            &temp.path().join("source.ti3").to_string_lossy(),
            false,
        )
        .unwrap();
        complete_build_profile(
            &config.database_path,
            &source_job.id,
            &temp.path().join("source.icc").to_string_lossy(),
            &ReviewSummaryRecord {
                result: "Pass".to_string(),
                verified_against_file: "source.ti3".to_string(),
                print_settings: "Premium Luster / 1440 dpi".to_string(),
                last_verification_date: Some("2026-04-20T12:00:00Z".to_string()),
                average_de00: Some(1.2),
                maximum_de00: Some(2.8),
                notes: "Good first build.".to_string(),
            },
        )
        .unwrap();
        let published = publish_new_profile(&config.database_path, &source_job.id).unwrap();
        let profile_id = published.published_profile_id.clone().unwrap();

        let dependent_job = create_new_profile_draft(
            &config.database_path,
            &config.app_support_path,
            &CreateNewProfileDraftInput {
                profile_name: Some("Planning Job".to_string()),
                printer_id: Some(printer.id.clone()),
                paper_id: Some(paper.id.clone()),
            },
        )
        .unwrap();
        save_target_settings(
            &config.database_path,
            &SaveTargetSettingsInput {
                job_id: dependent_job.id.clone(),
                patch_count: 928,
                improve_neutrals: false,
                use_existing_profile_to_help_target_planning: true,
                planning_profile_id: Some(profile_id.clone()),
            },
        )
        .unwrap();

        let result = delete_printer_profile(&config.database_path, &profile_id).unwrap();
        assert!(result.success);

        let profiles = list_printer_profiles(&config.database_path).unwrap();
        assert!(profiles.is_empty());

        let reopened = load_new_profile_job_detail(&config.database_path, &source_job.id).unwrap();
        assert_eq!(reopened.stage, WorkflowStage::Review);
        assert_eq!(reopened.status, "review");
        assert_eq!(reopened.next_action, "Publish the profile or return later");
        assert_eq!(reopened.published_profile_id, None);

        let dependent =
            load_new_profile_job_detail(&config.database_path, &dependent_job.id).unwrap();
        assert_eq!(dependent.target_settings.planning_profile_id, None);

        let snapshot = load_dashboard_snapshot(&config.database_path).unwrap();
        assert_eq!(snapshot.active_work_items.len(), 2);
        assert!(snapshot.active_work_items.iter().any(|item| {
            item.id == source_job.id
                && item.stage == WorkflowStage::Review
                && item.status == "review"
        }));
    }

    #[test]
    fn delete_printer_profile_succeeds_when_source_job_link_is_missing() {
        let temp = tempdir().unwrap();
        let config = build_config(temp.path());
        std::fs::create_dir_all(temp.path().join("app-support")).unwrap();

        initialize_database(&config).unwrap();
        let printer = create_printer(&config.database_path, &sample_printer_input()).unwrap();
        let paper = create_paper(
            &config.database_path,
            &CreatePaperInput {
                notes: "".to_string(),
                ..sample_paper_input()
            },
        )
        .unwrap();

        let source_job = create_new_profile_draft(
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
                job_id: source_job.id.clone(),
                profile_name: "P900 Rag v1".to_string(),
                printer_id: Some(printer.id.clone()),
                paper_id: Some(paper.id.clone()),
                printer_paper_preset_id: None,
                print_path: "Canon driver".to_string(),
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
        complete_measurement(
            &config.database_path,
            &source_job.id,
            &temp.path().join("source.ti3").to_string_lossy(),
            false,
        )
        .unwrap();
        complete_build_profile(
            &config.database_path,
            &source_job.id,
            &temp.path().join("source.icc").to_string_lossy(),
            &ReviewSummaryRecord {
                result: "Pass".to_string(),
                verified_against_file: "source.ti3".to_string(),
                print_settings: "Premium Luster / 1440 dpi".to_string(),
                last_verification_date: Some("2026-04-20T12:00:00Z".to_string()),
                average_de00: Some(1.2),
                maximum_de00: Some(2.8),
                notes: "Good first build.".to_string(),
            },
        )
        .unwrap();
        let published = publish_new_profile(&config.database_path, &source_job.id).unwrap();
        let profile_id = published.published_profile_id.clone().unwrap();

        let dependent_job = create_new_profile_draft(
            &config.database_path,
            &config.app_support_path,
            &CreateNewProfileDraftInput {
                profile_name: Some("Planning Job".to_string()),
                printer_id: Some(printer.id.clone()),
                paper_id: Some(paper.id.clone()),
            },
        )
        .unwrap();
        save_target_settings(
            &config.database_path,
            &SaveTargetSettingsInput {
                job_id: dependent_job.id.clone(),
                patch_count: 928,
                improve_neutrals: false,
                use_existing_profile_to_help_target_planning: true,
                planning_profile_id: Some(profile_id.clone()),
            },
        )
        .unwrap();

        let corruption = Connection::open(&config.database_path).unwrap();
        corruption
            .pragma_update(None, "foreign_keys", "OFF")
            .unwrap();
        corruption
            .execute(
                "UPDATE printer_profiles SET created_from_job_id = ?2 WHERE id = ?1",
                params![&profile_id, "job-missing"],
            )
            .unwrap();
        corruption
            .execute(
                "DELETE FROM new_profile_jobs WHERE id = ?1",
                params![&source_job.id],
            )
            .unwrap();
        corruption
            .execute("DELETE FROM jobs WHERE id = ?1", params![&source_job.id])
            .unwrap();
        corruption
            .pragma_update(None, "foreign_keys", "ON")
            .unwrap();

        let result = delete_printer_profile(&config.database_path, &profile_id).unwrap();
        assert!(result.success);

        let profiles = list_printer_profiles(&config.database_path).unwrap();
        assert!(profiles.is_empty());

        let dependent =
            load_new_profile_job_detail(&config.database_path, &dependent_job.id).unwrap();
        assert_eq!(dependent.target_settings.planning_profile_id, None);

        let connection = open_connection(&config.database_path).unwrap();
        let source_job_count: i64 = connection
            .query_row(
                "SELECT COUNT(*) FROM jobs WHERE id = ?1",
                params![&source_job.id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(source_job_count, 0);
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
    fn migration_backfills_paper_identity_without_guessing_specs() {
        let temp = tempdir().unwrap();
        let database_path = temp.path().join("legacy-paper.sqlite");
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
                CREATE TABLE papers (
                    id TEXT PRIMARY KEY,
                    vendor TEXT NOT NULL DEFAULT '',
                    product_name TEXT NOT NULL DEFAULT '',
                    surface_class TEXT NOT NULL DEFAULT '',
                    weight_thickness TEXT NOT NULL DEFAULT '',
                    oba_fluorescence_notes TEXT NOT NULL DEFAULT '',
                    notes TEXT NOT NULL DEFAULT '',
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                PRAGMA user_version = 4;
                INSERT INTO papers (
                    id,
                    vendor,
                    product_name,
                    surface_class,
                    weight_thickness,
                    oba_fluorescence_notes,
                    notes,
                    created_at,
                    updated_at
                )
                VALUES (
                    'paper-1',
                    'Canson',
                    'Rag Photographique',
                    'Matte',
                    '310 gsm / 0.47 mm',
                    'Low OBA',
                    'Gallery stock',
                    '2026-04-19T00:00:00Z',
                    '2026-04-19T00:00:00Z'
                );
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

        initialize_database(&config).unwrap();

        let paper = list_papers(&config.database_path).unwrap().remove(0);
        assert_eq!(paper.manufacturer, "Canson");
        assert_eq!(paper.paper_line, "Rag Photographique");
        assert_eq!(paper.oba_content, "Low OBA");
        assert_eq!(paper.basis_weight_value, "");
        assert_eq!(paper.thickness_value, "");
        assert!(paper.notes.contains("Gallery stock"));
        assert!(
            paper
                .notes
                .contains("Legacy weight/thickness: 310 gsm / 0.47 mm")
        );
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
                manufacturer: "Epson".to_string(),
                model: "P900".to_string(),
                nickname: "Studio P900".to_string(),
                transport_style: "Sheet-fed".to_string(),
                colorant_family: ColorantFamily::Cmyk,
                channel_count: 4,
                channel_labels: Vec::new(),
                supported_media_settings: vec!["Premium Luster".to_string()],
                supported_quality_modes: vec!["1440 dpi".to_string(), "2880 dpi".to_string()],
                monochrome_path_notes: "ABW".to_string(),
                notes: "North wall".to_string(),
            },
        )
        .unwrap();
        let paper = create_paper(&config.database_path, &sample_paper_input()).unwrap();

        let printers = list_printers(&config.database_path).unwrap();
        let papers = list_papers(&config.database_path).unwrap();

        assert_eq!(printers.len(), 1);
        assert_eq!(papers.len(), 1);
        assert_eq!(printers[0].id, printer.id);
        assert_eq!(papers[0].id, paper.id);
        assert_eq!(papers[0].manufacturer, "Canson");
        assert_eq!(papers[0].paper_line, "Rag");
        assert_eq!(papers[0].basis_weight_unit, PaperWeightUnit::Gsm);

        let updated = update_paper(
            &config.database_path,
            &UpdatePaperInput {
                id: paper.id.clone(),
                manufacturer: "Hahnemuhle".to_string(),
                paper_line: "William Turner".to_string(),
                surface_class: "Matte".to_string(),
                basis_weight_value: "310".to_string(),
                basis_weight_unit: PaperWeightUnit::Gsm,
                thickness_value: "0.62".to_string(),
                thickness_unit: PaperThicknessUnit::Mm,
                surface_texture: "Textured".to_string(),
                base_material: "100% cotton".to_string(),
                media_color: "White".to_string(),
                opacity: "99%".to_string(),
                whiteness: "88.5".to_string(),
                oba_content: "None".to_string(),
                ink_compatibility: "Pigment".to_string(),
                notes: "Archive stock".to_string(),
            },
        )
        .unwrap();

        assert_eq!(updated.manufacturer, "Hahnemuhle");
        assert_eq!(updated.paper_line, "William Turner");
        assert_eq!(updated.thickness_unit, PaperThicknessUnit::Mm);
        assert_eq!(updated.surface_texture, "Textured");
    }

    #[test]
    fn preset_round_trip_and_job_snapshots_remain_stable_after_updates() {
        let temp = tempdir().unwrap();
        let config = build_config(temp.path());
        std::fs::create_dir_all(temp.path().join("app-support")).unwrap();
        initialize_database(&config).unwrap();

        let printer = create_printer(
            &config.database_path,
            &CreatePrinterInput {
                manufacturer: "Epson".to_string(),
                model: "P900".to_string(),
                nickname: "Studio P900".to_string(),
                transport_style: "Sheet-fed".to_string(),
                colorant_family: ColorantFamily::Cmyk,
                channel_count: 4,
                channel_labels: Vec::new(),
                supported_media_settings: vec![
                    "Premium Luster".to_string(),
                    "Ultra Premium Presentation Matte".to_string(),
                ],
                supported_quality_modes: vec!["1440 dpi".to_string(), "2880 dpi".to_string()],
                monochrome_path_notes: "ABW".to_string(),
                notes: String::new(),
            },
        )
        .unwrap();
        let paper = create_paper(&config.database_path, &sample_paper_input()).unwrap();
        let preset = create_printer_paper_preset(
            &config.database_path,
            &CreatePrinterPaperPresetInput {
                printer_id: printer.id.clone(),
                paper_id: paper.id.clone(),
                label: "Studio Matte".to_string(),
                print_path: "Mirage".to_string(),
                media_setting: "Premium Luster".to_string(),
                quality_mode: "1440 dpi".to_string(),
                total_ink_limit_percent: Some(280),
                black_ink_limit_percent: Some(90),
                notes: "Primary path".to_string(),
            },
        )
        .unwrap();

        let presets = list_printer_paper_presets(&config.database_path).unwrap();
        assert_eq!(presets.len(), 1);
        assert_eq!(presets[0].id, preset.id);

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
                printer_paper_preset_id: Some(preset.id.clone()),
                print_path: preset.print_path.clone(),
                media_setting: preset.media_setting.clone(),
                quality_mode: preset.quality_mode.clone(),
                print_path_notes: "Rear tray".to_string(),
                measurement_notes: String::new(),
                measurement_observer: "1931_2".to_string(),
                measurement_illuminant: "D50".to_string(),
                measurement_mode: MeasurementMode::Strip,
            },
        )
        .unwrap();

        update_printer(
            &config.database_path,
            &UpdatePrinterInput {
                id: printer.id.clone(),
                manufacturer: "Epson".to_string(),
                model: "P900".to_string(),
                nickname: "Studio P900".to_string(),
                transport_style: "Sheet-fed".to_string(),
                colorant_family: ColorantFamily::ExtendedN,
                channel_count: 6,
                channel_labels: vec![
                    "C".to_string(),
                    "M".to_string(),
                    "Y".to_string(),
                    "K".to_string(),
                    "Lc".to_string(),
                    "Lm".to_string(),
                ],
                supported_media_settings: vec![
                    "Premium Luster".to_string(),
                    "Ultra Premium Presentation Matte".to_string(),
                ],
                supported_quality_modes: vec!["1440 dpi".to_string(), "2880 dpi".to_string()],
                monochrome_path_notes: "ABW".to_string(),
                notes: String::new(),
            },
        )
        .unwrap();
        update_printer_paper_preset(
            &config.database_path,
            &UpdatePrinterPaperPresetInput {
                id: preset.id.clone(),
                printer_id: printer.id.clone(),
                paper_id: paper.id.clone(),
                label: "Studio Matte".to_string(),
                print_path: "Photoshop -> Canon driver".to_string(),
                media_setting: "Ultra Premium Presentation Matte".to_string(),
                quality_mode: "2880 dpi".to_string(),
                total_ink_limit_percent: Some(300),
                black_ink_limit_percent: Some(95),
                notes: "Updated path".to_string(),
            },
        )
        .unwrap();

        let detail = load_new_profile_job_detail(&config.database_path, &job.id).unwrap();
        assert_eq!(
            detail.context.printer_paper_preset_id,
            Some(preset.id.clone())
        );
        assert_eq!(detail.context.print_path, "Mirage");
        assert_eq!(detail.context.media_setting, "Premium Luster");
        assert_eq!(detail.context.quality_mode, "1440 dpi");
        assert_eq!(detail.context.colorant_family, ColorantFamily::Cmyk);
        assert_eq!(detail.context.channel_count, 4);
        assert_eq!(detail.context.total_ink_limit_percent, Some(280));
        assert_eq!(detail.context.black_ink_limit_percent, Some(90));

        let runner_context =
            load_new_profile_runner_context(&config.database_path, &job.id).unwrap();
        assert_eq!(runner_context.colorant_family, ColorantFamily::Cmyk);
        assert_eq!(runner_context.channel_count, 4);
        assert_eq!(runner_context.print_path, "Mirage");
        assert_eq!(runner_context.media_setting, "Premium Luster");
        assert_eq!(runner_context.quality_mode, "1440 dpi");
        assert_eq!(runner_context.total_ink_limit_percent, Some(280));
        assert_eq!(runner_context.black_ink_limit_percent, Some(90));
    }
}
