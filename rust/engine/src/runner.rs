use crate::db;
use crate::logging;
use crate::model::{
    CommandStream, MeasurementMode, ReviewSummaryRecord, ToolchainStatus, WorkflowStage,
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

    let mut targen_args = vec![
        "-v".to_string(),
        "-G".to_string(),
        "-d4".to_string(),
        "-f".to_string(),
        context.patch_count.to_string(),
    ];
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

    run_command_with_transcript(
        config,
        context,
        WorkflowStage::Target,
        "targen",
        &targen_path,
        &targen_args,
        Some(Path::new(&context.workspace_path)),
    )?;

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
    printtarg_args.push(basename.to_string_lossy().to_string());

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

    let colprof_args = vec![
        "-v".to_string(),
        "-D".to_string(),
        context.profile_name.clone(),
        "-A".to_string(),
        context.printer_name.clone(),
        "-M".to_string(),
        context.paper_name.clone(),
        "-O".to_string(),
        profile_path.to_string_lossy().to_string(),
        basename.to_string_lossy().to_string(),
    ];
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
        print_settings: format!(
            "{} | {}",
            blank_fallback(&context.media_setting, "Media setting not recorded"),
            blank_fallback(&context.quality_mode, "Quality mode not recorded")
        ),
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

fn error_stage(task: &JobTask) -> WorkflowStage {
    match task {
        JobTask::GenerateTarget => WorkflowStage::Target,
        JobTask::MeasureTarget => WorkflowStage::Measure,
        JobTask::BuildProfile => WorkflowStage::Build,
    }
}
