use crate::model::LogEntry;
use crate::support::{EngineResult, ensure_directory, iso_timestamp};
use std::fs::OpenOptions;
use std::io::{BufRead, BufReader, Write};
use std::path::Path;

pub fn append_log(log_path: &str, level: &str, source: &str, message: impl Into<String>) {
    if let Err(error) = append_log_impl(log_path, level, source, message.into()) {
        eprintln!("argyllux logging failed: {error}");
    }
}

pub fn read_recent_logs(log_path: &str, limit: usize) -> Vec<LogEntry> {
    let file = match std::fs::File::open(log_path) {
        Ok(file) => file,
        Err(_) => return Vec::new(),
    };

    let reader = BufReader::new(file);
    let mut entries = reader
        .lines()
        .filter_map(|line| line.ok())
        .filter_map(|line| serde_json::from_str::<LogEntry>(&line).ok())
        .collect::<Vec<_>>();

    if entries.len() > limit {
        entries.drain(..entries.len() - limit);
    }

    entries
}

fn append_log_impl(log_path: &str, level: &str, source: &str, message: String) -> EngineResult<()> {
    let path = Path::new(log_path);
    if let Some(parent) = path.parent() {
        ensure_directory(parent)?;
    }

    let mut file = OpenOptions::new().create(true).append(true).open(path)?;
    let entry = LogEntry {
        timestamp: iso_timestamp(),
        level: level.to_string(),
        message,
        source: source.to_string(),
    };
    let line = serde_json::to_string(&entry)?;
    writeln!(file, "{line}")?;
    Ok(())
}
