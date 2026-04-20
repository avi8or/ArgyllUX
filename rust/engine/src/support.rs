use chrono::Utc;
use std::io;
use std::path::{Path, PathBuf};

pub type EngineResult<T> = Result<T, Box<dyn std::error::Error + Send + Sync>>;

pub fn sanitize_optional_path(value: Option<String>) -> Option<String> {
    value.and_then(|path| {
        let trimmed = path.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_string())
        }
    })
}

pub fn sanitize_search_roots(values: Vec<String>) -> Vec<String> {
    values
        .into_iter()
        .filter_map(|value| {
            let trimmed = value.trim();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            }
        })
        .collect()
}

pub fn iso_timestamp() -> String {
    Utc::now().to_rfc3339()
}

pub fn ensure_runtime_paths(app_support_path: &str, database_path: &str, log_path: &str) -> bool {
    let mut ok = true;

    ok &= ensure_directory(Path::new(app_support_path)).is_ok();

    if let Some(parent) = Path::new(database_path).parent() {
        ok &= ensure_directory(parent).is_ok();
    }

    if let Some(parent) = Path::new(log_path).parent() {
        ok &= ensure_directory(parent).is_ok();
    }

    ok
}

pub fn ensure_directory(path: &Path) -> io::Result<()> {
    std::fs::create_dir_all(path)
}

pub fn normalized_directory_candidates(path: &Path) -> Vec<PathBuf> {
    let base = if path.is_file() {
        path.parent().unwrap_or(path).to_path_buf()
    } else {
        path.to_path_buf()
    };

    let mut candidates = Vec::new();
    let file_name = base.file_name().and_then(|name| name.to_str());

    if file_name == Some("bin") {
        candidates.push(base);
    } else {
        candidates.push(base.join("bin"));
        candidates.push(base);
    }

    candidates
}
