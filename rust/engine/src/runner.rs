use crate::db;
use crate::diagnostics;
use crate::logging;
use crate::model::{
    ColorantFamily, CommandStream, DiagnosticCategory, DiagnosticEventInput, DiagnosticLevel,
    DiagnosticPrivacy, MeasurementMode, ReviewSummaryRecord, ToolchainStatus, WorkflowStage,
};
use crate::support::EngineResult;
use crate::support::ensure_directory;
use std::io::{BufRead, BufReader, Read};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::sync::atomic::{AtomicU32, Ordering};

#[derive(Debug, Clone)]
pub enum JobTask {
    GenerateTarget,
    MeasureTarget,
    BuildProfile,
}

pub fn spawn_job_task(
    config: crate::model::EngineConfig,
    toolchain_status: ToolchainStatus,
    job_id: String,
    task: JobTask,
) {
    let failure_stage = error_stage(&task);
    std::thread::spawn(move || {
        if let Err(error) = run_job_task(&config, &toolchain_status, &job_id, task) {
            let stage = failure_stage.clone();
            let message = error.to_string();
            let _ = db::mark_job_failed(&config.database_path, &job_id, stage.clone(), &message);
            logging::append_log(
                &config.log_path,
                "error",
                "engine.workflow",
                format!("Job {job_id} failed during {:?}: {message}", stage),
            );
        }
    });
}

fn run_job_task(
    config: &crate::model::EngineConfig,
    toolchain_status: &ToolchainStatus,
    job_id: &str,
    task: JobTask,
) -> EngineResult<()> {
    let context = db::load_new_profile_runner_context(&config.database_path, job_id)?;
    ensure_directory(Path::new(&context.workspace_path))?;

    match task {
        JobTask::GenerateTarget => run_generate_target(config, toolchain_status, &context),
        JobTask::MeasureTarget => run_measure_target(config, toolchain_status, &context),
        JobTask::BuildProfile => run_build_profile(config, toolchain_status, &context),
    }
}

fn run_generate_target(
    config: &crate::model::EngineConfig,
    toolchain_status: &ToolchainStatus,
    context: &db::NewProfileRunnerContext,
) -> EngineResult<()> {
    let basename = base_path(context);
    let targen_path = resolve_executable_path(toolchain_status, "targen")?;
    let printtarg_path = resolve_executable_path(toolchain_status, "printtarg")?;

    let targen_args = build_targen_args(context, &basename);

    run_command_with_transcript(
        config,
        context,
        WorkflowStage::Target,
        "targen",
        &targen_path,
        &targen_args,
        Some(Path::new(&context.workspace_path)),
    )?;

    let printtarg_args = build_printtarg_args(context, &basename);

    run_command_with_transcript(
        config,
        context,
        WorkflowStage::Target,
        "printtarg",
        &printtarg_path,
        &printtarg_args,
        Some(Path::new(&context.workspace_path)),
    )?;

    let ti1 = with_extension(&basename, "ti1");
    let ti2 = with_extension(&basename, "ti2");
    let tif = with_extension(&basename, "tif");
    let cht = with_extension(&basename, "cht");

    db::complete_generate_target(
        &config.database_path,
        &context.job_id,
        &ti1.to_string_lossy(),
        &ti2.to_string_lossy(),
        &tif.to_string_lossy(),
        cht.exists()
            .then(|| cht.to_string_lossy().to_string())
            .as_deref(),
    )?;

    logging::append_log(
        &config.log_path,
        "info",
        "engine.workflow",
        format!("Generated target files for {}.", context.title),
    );

    Ok(())
}

fn run_measure_target(
    config: &crate::model::EngineConfig,
    toolchain_status: &ToolchainStatus,
    context: &db::NewProfileRunnerContext,
) -> EngineResult<()> {
    let basename = base_path(context);
    let measurement_path = with_extension(&basename, "ti3");

    match context.measurement_mode {
        MeasurementMode::ScanFile => {
            let scan_file_path = context
                .scan_file_path
                .clone()
                .ok_or("Scan File mode requires a scan file path.")?;
            let scanin_path = resolve_executable_path(toolchain_status, "scanin")?;
            let scanin_args = vec![
                "-v".to_string(),
                "-O".to_string(),
                measurement_path.to_string_lossy().to_string(),
                scan_file_path,
                with_extension(&basename, "cht")
                    .to_string_lossy()
                    .to_string(),
                with_extension(&basename, "ti2")
                    .to_string_lossy()
                    .to_string(),
            ];
            run_command_with_transcript(
                config,
                context,
                WorkflowStage::Measure,
                "scanin",
                &scanin_path,
                &scanin_args,
                Some(Path::new(&context.workspace_path)),
            )?;
            db::complete_measurement(
                &config.database_path,
                &context.job_id,
                &measurement_path.to_string_lossy(),
                false,
            )?;
        }
        MeasurementMode::Strip | MeasurementMode::Patch => {
            let chartread_path = resolve_executable_path(toolchain_status, "chartread")?;
            let mut chartread_args = vec!["-v".to_string()];
            if matches!(context.measurement_mode, MeasurementMode::Patch) {
                chartread_args.push("-p".to_string());
            }
            if context.has_measurement_checkpoint {
                chartread_args.push("-r".to_string());
            }
            if !context.measurement_observer.trim().is_empty() {
                chartread_args.push("-Q".to_string());
                chartread_args.push(context.measurement_observer.clone());
            }
            chartread_args.push(basename.to_string_lossy().to_string());

            let chartread_result = run_command_with_transcript(
                config,
                context,
                WorkflowStage::Measure,
                "chartread",
                &chartread_path,
                &chartread_args,
                Some(Path::new(&context.workspace_path)),
            );

            match chartread_result {
                Ok(_) => {
                    db::complete_measurement(
                        &config.database_path,
                        &context.job_id,
                        &measurement_path.to_string_lossy(),
                        false,
                    )?;
                }
                Err(error) => {
                    if measurement_path.exists() {
                        let _ = db::complete_measurement(
                            &config.database_path,
                            &context.job_id,
                            &measurement_path.to_string_lossy(),
                            true,
                        );
                    }
                    return Err(error);
                }
            }
        }
    }

    logging::append_log(
        &config.log_path,
        "info",
        "engine.workflow",
        format!("Captured measurements for {}.", context.title),
    );

    Ok(())
}

fn run_build_profile(
    config: &crate::model::EngineConfig,
    toolchain_status: &ToolchainStatus,
    context: &db::NewProfileRunnerContext,
) -> EngineResult<()> {
    let basename = base_path(context);
    let measurement_path = context
        .measurement_source_path
        .clone()
        .ok_or("Measure the target before building the profile.")?;
    let profile_path = with_extension(&basename, "icc");
    let colprof_path = resolve_executable_path(toolchain_status, "colprof")?;
    let profcheck_path = resolve_executable_path(toolchain_status, "profcheck")?;

    let colprof_args = build_colprof_args(context, &basename, &profile_path);
    run_command_with_transcript(
        config,
        context,
        WorkflowStage::Build,
        "colprof",
        &colprof_path,
        &colprof_args,
        Some(Path::new(&context.workspace_path)),
    )?;

    let profcheck_args = vec![
        "-v".to_string(),
        "1".to_string(),
        "-k".to_string(),
        measurement_path.clone(),
        profile_path.to_string_lossy().to_string(),
    ];
    let transcript = run_command_with_transcript(
        config,
        context,
        WorkflowStage::Build,
        "profcheck",
        &profcheck_path,
        &profcheck_args,
        Some(Path::new(&context.workspace_path)),
    )?;

    let review_summary = build_review_summary(context, &measurement_path, &transcript);
    db::complete_build_profile(
        &config.database_path,
        &context.job_id,
        &profile_path.to_string_lossy(),
        &review_summary,
    )?;

    logging::append_log(
        &config.log_path,
        "info",
        "engine.workflow",
        format!("Built profile for {}.", context.title),
    );

    Ok(())
}

fn run_command_with_transcript(
    config: &crate::model::EngineConfig,
    context: &db::NewProfileRunnerContext,
    stage: WorkflowStage,
    label: &str,
    program_path: &Path,
    args: &[String],
    working_directory: Option<&Path>,
) -> EngineResult<String> {
    let argv = std::iter::once(program_path.to_string_lossy().to_string())
        .chain(args.iter().cloned())
        .collect::<Vec<_>>();
    let command_id = db::insert_job_command(
        &config.database_path,
        &context.job_id,
        stage.clone(),
        label,
        &argv,
    )?;
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

    logging::append_log(
        &config.log_path,
        "info",
        "engine.cli",
        format!("Starting {} for job {}.", label, context.job_id),
    );
    db::append_job_command_event(
        &config.database_path,
        &command_id,
        CommandStream::System,
        0,
        &format!("$ {}", argv.join(" ")),
    )?;

    let mut command = Command::new(program_path);
    command.args(args);
    command.stdout(Stdio::piped()).stderr(Stdio::piped());
    if let Some(working_directory) = working_directory {
        command.current_dir(working_directory);
    }

    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => {
            db::append_job_command_event(
                &config.database_path,
                &command_id,
                CommandStream::System,
                1,
                &format!("Failed to start {}: {}", label, error),
            )?;
            db::finish_job_command(&config.database_path, &command_id, false, None)?;
            let _ = db::record_diagnostic_event(
                &config.database_path,
                &DiagnosticEventInput {
                    level: DiagnosticLevel::Error,
                    category: DiagnosticCategory::Cli,
                    source: "engine.cli".to_string(),
                    message: format!("Failed to start {label}."),
                    details_json: diagnostics::command_summary_details(
                        label,
                        &argv,
                        "failed_to_start",
                        None,
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
            return Err(error.into());
        }
    };

    let line_counter = Arc::new(AtomicU32::new(1));
    let stdout_handle = spawn_stream_reader(
        &config.database_path,
        &command_id,
        CommandStream::Stdout,
        child.stdout.take(),
        line_counter.clone(),
    );
    let stderr_handle = spawn_stream_reader(
        &config.database_path,
        &command_id,
        CommandStream::Stderr,
        child.stderr.take(),
        line_counter,
    );

    let status = child.wait()?;
    if let Some(stdout_handle) = stdout_handle {
        let _ = stdout_handle.join();
    }
    if let Some(stderr_handle) = stderr_handle {
        let _ = stderr_handle.join();
    }

    let succeeded = status.success();
    db::finish_job_command(&config.database_path, &command_id, succeeded, status.code())?;
    let _ = db::record_diagnostic_event(
        &config.database_path,
        &DiagnosticEventInput {
            level: if succeeded {
                DiagnosticLevel::Info
            } else {
                DiagnosticLevel::Error
            },
            category: DiagnosticCategory::Cli,
            source: "engine.cli".to_string(),
            message: format!(
                "{} {label}.",
                if succeeded {
                    "Finished"
                } else {
                    "Command failed"
                }
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
    logging::append_log(
        &config.log_path,
        if succeeded { "info" } else { "error" },
        "engine.cli",
        format!(
            "{} {} with exit code {:?}.",
            if succeeded {
                "Finished"
            } else {
                "Command failed"
            },
            label,
            status.code()
        ),
    );

    let events = db::load_new_profile_job_detail(&config.database_path, &context.job_id)?
        .commands
        .into_iter()
        .find(|command| command.id == command_id)
        .map(|command| {
            command
                .events
                .into_iter()
                .filter(|event| {
                    matches!(event.stream, CommandStream::Stdout | CommandStream::Stderr)
                })
                .map(|event| event.message)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let transcript = events.join("\n");

    if !succeeded {
        return Err(format!("{} failed with exit code {:?}.", label, status.code()).into());
    }

    Ok(transcript)
}

fn duration_ms_since(started_at: std::time::Instant) -> u32 {
    duration_ms_from_millis(started_at.elapsed().as_millis())
}

fn duration_ms_from_millis(millis: u128) -> u32 {
    millis.min(u32::MAX as u128) as u32
}

fn spawn_stream_reader(
    database_path: &str,
    command_id: &str,
    stream: CommandStream,
    reader: Option<impl Read + Send + 'static>,
    line_counter: Arc<AtomicU32>,
) -> Option<std::thread::JoinHandle<()>> {
    let reader = reader?;
    let database_path = database_path.to_string();
    let command_id = command_id.to_string();
    Some(std::thread::spawn(move || {
        let reader = BufReader::new(reader);
        for line in reader.lines().map_while(Result::ok) {
            let line_number = line_counter.fetch_add(1, Ordering::Relaxed) + 1;
            let _ = db::append_job_command_event(
                &database_path,
                &command_id,
                stream.clone(),
                line_number,
                &line,
            );
        }
    }))
}

fn resolve_executable_path(
    toolchain_status: &ToolchainStatus,
    executable: &str,
) -> EngineResult<PathBuf> {
    let root = toolchain_status
        .resolved_install_path
        .as_deref()
        .ok_or("ArgyllCMS is not ready.")?;
    Ok(Path::new(root).join(executable))
}

fn base_path(context: &db::NewProfileRunnerContext) -> PathBuf {
    Path::new(&context.workspace_path).join(sanitize_file_stem(&context.profile_name))
}

fn with_extension(base: &Path, extension: &str) -> PathBuf {
    let mut path = base.to_path_buf();
    path.set_extension(extension);
    path
}

fn sanitize_file_stem(value: &str) -> String {
    let mut sanitized = value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() {
                character.to_ascii_lowercase()
            } else {
                '-'
            }
        })
        .collect::<String>();
    while sanitized.contains("--") {
        sanitized = sanitized.replace("--", "-");
    }
    sanitized = sanitized.trim_matches('-').to_string();
    if sanitized.is_empty() {
        "new-profile".to_string()
    } else {
        sanitized
    }
}

fn build_review_summary(
    context: &db::NewProfileRunnerContext,
    measurement_path: &str,
    transcript: &str,
) -> ReviewSummaryRecord {
    let average_de00 = find_metric(transcript, &["average", "avg"]);
    let maximum_de00 = find_metric(transcript, &["maximum", "max"]);
    let result = match (average_de00, maximum_de00) {
        (Some(average), Some(maximum)) => {
            format!("Result: avg dE00 {:.1}, max {:.1}", average, maximum)
        }
        _ => "Result: verification summary available in the technical transcript".to_string(),
    };

    ReviewSummaryRecord {
        result,
        verified_against_file: measurement_path.to_string(),
        print_settings: build_print_settings_summary(context),
        last_verification_date: Some(crate::support::iso_timestamp()),
        average_de00,
        maximum_de00,
        notes: transcript
            .lines()
            .rev()
            .find(|line| !line.trim().is_empty())
            .unwrap_or_default()
            .to_string(),
    }
}

fn find_metric(transcript: &str, markers: &[&str]) -> Option<f64> {
    transcript.lines().find_map(|line| {
        let lowered = line.to_ascii_lowercase();
        if markers.iter().any(|marker| lowered.contains(marker)) {
            extract_first_float(&lowered)
        } else {
            None
        }
    })
}

fn extract_first_float(value: &str) -> Option<f64> {
    let mut buffer = String::new();
    for character in value.chars() {
        if character.is_ascii_digit() || character == '.' {
            buffer.push(character);
        } else if !buffer.is_empty() {
            if let Ok(parsed) = buffer.parse::<f64>() {
                return Some(parsed);
            }
            buffer.clear();
        }
    }

    if buffer.is_empty() {
        None
    } else {
        buffer.parse::<f64>().ok()
    }
}

fn blank_fallback(value: &str, fallback: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        fallback.to_string()
    } else {
        trimmed.to_string()
    }
}

fn blank_metadata(primary: &str, fallback: &str) -> String {
    let trimmed_primary = primary.trim();
    if trimmed_primary.is_empty() {
        fallback.trim().to_string()
    } else {
        trimmed_primary.to_string()
    }
}

fn build_print_settings_summary(context: &db::NewProfileRunnerContext) -> String {
    let mut parts = Vec::new();
    if !context.print_path.trim().is_empty() {
        parts.push(context.print_path.trim().to_string());
    }
    parts.push(blank_fallback(
        &context.media_setting,
        "Media setting not recorded",
    ));
    parts.push(blank_fallback(
        &context.quality_mode,
        "Quality mode not recorded",
    ));
    parts.push(channel_setup_label(context));

    let options_suffix = build_options_suffix(context);
    if options_suffix.is_empty() {
        parts.join(" | ")
    } else {
        format!("{}{}", parts.join(" | "), options_suffix)
    }
}

fn build_targen_args(context: &db::NewProfileRunnerContext, basename: &Path) -> Vec<String> {
    let mut targen_args = vec![
        "-v".to_string(),
        "-G".to_string(),
        format!("-d{}", targen_device_code(context)),
        "-f".to_string(),
        context.patch_count.to_string(),
    ];
    if let Some(total_ink_limit_percent) = context.total_ink_limit_percent {
        targen_args.push("-l".to_string());
        targen_args.push(total_ink_limit_percent.to_string());
    }
    if context.improve_neutrals {
        targen_args.push("-n".to_string());
        targen_args.push("16".to_string());
        targen_args.push("-N".to_string());
        targen_args.push("0.75".to_string());
    }
    if let Some(planning_profile_path) = &context.planning_profile_path {
        targen_args.push("-c".to_string());
        targen_args.push(planning_profile_path.clone());
    }
    targen_args.push(basename.to_string_lossy().to_string());
    targen_args
}

fn build_printtarg_args(context: &db::NewProfileRunnerContext, basename: &Path) -> Vec<String> {
    let mut printtarg_args = vec![
        "-v".to_string(),
        "-p".to_string(),
        "A4".to_string(),
        "-T".to_string(),
        "300".to_string(),
    ];
    if matches!(context.measurement_mode, MeasurementMode::ScanFile) {
        printtarg_args.push("-s".to_string());
    }
    if context.channel_count > 4 {
        printtarg_args.push("-N".to_string());
    }
    printtarg_args.push(basename.to_string_lossy().to_string());
    printtarg_args
}

fn build_colprof_args(
    context: &db::NewProfileRunnerContext,
    basename: &Path,
    profile_path: &Path,
) -> Vec<String> {
    let mut colprof_args = vec![
        "-v".to_string(),
        "-D".to_string(),
        context.profile_name.clone(),
        "-A".to_string(),
        blank_metadata(&context.printer_manufacturer, &context.printer_name),
        "-M".to_string(),
        blank_metadata(&context.printer_model, &context.printer_name),
        "-O".to_string(),
        profile_path.to_string_lossy().to_string(),
    ];
    if let Some(total_ink_limit_percent) = context.total_ink_limit_percent {
        colprof_args.push("-l".to_string());
        colprof_args.push(total_ink_limit_percent.to_string());
    }
    if let Some(black_ink_limit_percent) = context.black_ink_limit_percent
        && has_black_channel(context)
    {
        colprof_args.push("-L".to_string());
        colprof_args.push(black_ink_limit_percent.to_string());
    }
    colprof_args.push(basename.to_string_lossy().to_string());
    colprof_args
}

fn targen_device_code(context: &db::NewProfileRunnerContext) -> u32 {
    match context.colorant_family {
        ColorantFamily::GrayK => 0,
        ColorantFamily::Rgb => 2,
        ColorantFamily::Cmy => 5,
        ColorantFamily::Cmyk => 4,
        ColorantFamily::ExtendedN => context.channel_count.max(6),
    }
}

fn channel_setup_label(context: &db::NewProfileRunnerContext) -> String {
    match context.colorant_family {
        ColorantFamily::GrayK => "Gray/K (1 channel)".to_string(),
        ColorantFamily::Rgb => "RGB (3 channels)".to_string(),
        ColorantFamily::Cmy => "CMY (3 channels)".to_string(),
        ColorantFamily::Cmyk => "CMYK (4 channels)".to_string(),
        ColorantFamily::ExtendedN => {
            if context.channel_labels.is_empty() {
                format!("Extended N-color ({} channels)", context.channel_count)
            } else {
                format!(
                    "Extended N-color ({} channels: {})",
                    context.channel_count,
                    context.channel_labels.join(", ")
                )
            }
        }
    }
}

fn build_options_suffix(context: &db::NewProfileRunnerContext) -> String {
    let mut parts = Vec::new();
    if let Some(total_ink_limit_percent) = context.total_ink_limit_percent {
        parts.push(format!("TAC {}%", total_ink_limit_percent));
    }
    if let Some(black_ink_limit_percent) = context.black_ink_limit_percent {
        parts.push(format!("Black {}%", black_ink_limit_percent));
    }
    if parts.is_empty() {
        String::new()
    } else {
        format!(" | {}", parts.join(" | "))
    }
}

fn has_black_channel(context: &db::NewProfileRunnerContext) -> bool {
    match context.colorant_family {
        ColorantFamily::GrayK | ColorantFamily::Cmyk => true,
        ColorantFamily::ExtendedN => context.channel_labels.iter().any(|label| {
            let lowered = label.trim().to_ascii_lowercase();
            lowered == "k" || lowered == "black"
        }),
        ColorantFamily::Rgb | ColorantFamily::Cmy => false,
    }
}

fn error_stage(task: &JobTask) -> WorkflowStage {
    match task {
        JobTask::GenerateTarget => WorkflowStage::Target,
        JobTask::MeasureTarget => WorkflowStage::Measure,
        JobTask::BuildProfile => WorkflowStage::Build,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_context() -> db::NewProfileRunnerContext {
        db::NewProfileRunnerContext {
            job_id: "job-1".to_string(),
            title: "P900 Rag v1".to_string(),
            profile_name: "P900 Rag v1".to_string(),
            printer_name: "Studio P900".to_string(),
            printer_manufacturer: "Epson".to_string(),
            printer_model: "SureColor P900".to_string(),
            workspace_path: "/tmp/job-1".to_string(),
            print_path: "Mirage".to_string(),
            media_setting: "Premium Luster".to_string(),
            quality_mode: "1440 dpi".to_string(),
            colorant_family: ColorantFamily::Cmyk,
            channel_count: 4,
            channel_labels: Vec::new(),
            total_ink_limit_percent: None,
            black_ink_limit_percent: None,
            measurement_observer: "1931_2".to_string(),
            measurement_mode: MeasurementMode::Strip,
            patch_count: 928,
            improve_neutrals: true,
            planning_profile_path: None,
            measurement_source_path: Some("/tmp/job-1/measurements.ti3".to_string()),
            scan_file_path: None,
            has_measurement_checkpoint: false,
        }
    }

    #[test]
    fn targen_args_follow_argyll_channel_device_codes() {
        let basename = Path::new("job-1/profile");
        let cases = [
            (ColorantFamily::GrayK, 1, Vec::new(), "-d0"),
            (ColorantFamily::Rgb, 3, Vec::new(), "-d2"),
            (ColorantFamily::Cmy, 3, Vec::new(), "-d5"),
            (ColorantFamily::Cmyk, 4, Vec::new(), "-d4"),
            (
                ColorantFamily::ExtendedN,
                6,
                vec![
                    "C".to_string(),
                    "M".to_string(),
                    "Y".to_string(),
                    "K".to_string(),
                ],
                "-d6",
            ),
        ];

        for (family, channel_count, channel_labels, expected_device_arg) in cases {
            let mut context = sample_context();
            context.colorant_family = family;
            context.channel_count = channel_count;
            context.channel_labels = channel_labels;
            let args = build_targen_args(&context, basename);

            assert!(
                args.iter().any(|arg| arg == expected_device_arg),
                "missing {expected_device_arg} in {:?}",
                args
            );
        }
    }

    #[test]
    fn targen_legacy_cmyk_context_stays_on_current_default_device_code() {
        let args = build_targen_args(&sample_context(), Path::new("job-1/profile"));
        assert!(args.iter().any(|arg| arg == "-d4"));
    }

    #[test]
    fn colprof_args_use_structured_metadata_and_limit_flags() {
        let basename = Path::new("job-1/profile");
        let profile_path = Path::new("/tmp/job-1/profile.icc");

        let mut cmyk_context = sample_context();
        cmyk_context.total_ink_limit_percent = Some(280);
        cmyk_context.black_ink_limit_percent = Some(90);
        let cmyk_args = build_colprof_args(&cmyk_context, basename, profile_path);
        assert!(
            cmyk_args
                .windows(2)
                .any(|pair| pair[0] == "-A" && pair[1] == "Epson")
        );
        assert!(
            cmyk_args
                .windows(2)
                .any(|pair| pair[0] == "-M" && pair[1] == "SureColor P900")
        );
        assert!(
            cmyk_args
                .windows(2)
                .any(|pair| pair[0] == "-l" && pair[1] == "280")
        );
        assert!(
            cmyk_args
                .windows(2)
                .any(|pair| pair[0] == "-L" && pair[1] == "90")
        );

        let mut rgb_context = sample_context();
        rgb_context.colorant_family = ColorantFamily::Rgb;
        rgb_context.channel_count = 3;
        rgb_context.total_ink_limit_percent = Some(240);
        rgb_context.black_ink_limit_percent = Some(75);
        let rgb_args = build_colprof_args(&rgb_context, basename, profile_path);
        assert!(
            rgb_args
                .windows(2)
                .any(|pair| pair[0] == "-l" && pair[1] == "240")
        );
        assert!(!rgb_args.iter().any(|arg| arg == "-L"));

        let mut extended_context = sample_context();
        extended_context.colorant_family = ColorantFamily::ExtendedN;
        extended_context.channel_count = 6;
        extended_context.channel_labels = vec![
            "C".to_string(),
            "M".to_string(),
            "Y".to_string(),
            "K".to_string(),
            "Lc".to_string(),
            "Lm".to_string(),
        ];
        extended_context.black_ink_limit_percent = Some(85);
        let extended_args = build_colprof_args(&extended_context, basename, profile_path);
        assert!(
            extended_args
                .windows(2)
                .any(|pair| pair[0] == "-L" && pair[1] == "85")
        );
    }

    #[test]
    fn print_path_is_context_only_and_does_not_change_command_args() {
        let basename = Path::new("job-1/profile");
        let profile_path = Path::new("/tmp/job-1/profile.icc");
        let mut context = sample_context();
        let baseline_targen = build_targen_args(&context, basename);
        let baseline_colprof = build_colprof_args(&context, basename, profile_path);

        context.print_path = "Photoshop -> Canon driver".to_string();

        assert_eq!(build_targen_args(&context, basename), baseline_targen);
        assert_eq!(
            build_colprof_args(&context, basename, profile_path),
            baseline_colprof
        );
        assert!(build_print_settings_summary(&context).starts_with("Photoshop -> Canon driver |"));
    }

    #[test]
    fn command_duration_ms_uses_saturating_milliseconds() {
        assert_eq!(duration_ms_from_millis(42), 42);
        assert_eq!(duration_ms_from_millis(u32::MAX as u128), u32::MAX);
        assert_eq!(duration_ms_from_millis(u32::MAX as u128 + 1), u32::MAX);
    }
}
