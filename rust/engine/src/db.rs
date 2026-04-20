use crate::model::{EngineConfig, ToolchainState, ToolchainStatus};
use crate::support::{EngineResult, iso_timestamp};
use rusqlite::{Connection, OptionalExtension, params};
use std::path::Path;

const TOOLCHAIN_OVERRIDE_KEY: &str = "toolchain.override_path";

pub struct DatabaseStatus {
    pub initialized: bool,
    pub migrations_applied: bool,
    pub persisted_override_path: Option<String>,
}

pub fn initialize_database(config: &EngineConfig) -> EngineResult<DatabaseStatus> {
    let database_exists = Path::new(&config.database_path).exists();
    let connection = open_connection(&config.database_path)?;
    let migrations_applied = apply_migrations(&connection)?;
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
            last_validation_time
        )
        VALUES (1, ?1, ?2, ?3, ?4, ?5)
        ON CONFLICT(id) DO UPDATE SET
            state = excluded.state,
            resolved_install_path = excluded.resolved_install_path,
            discovered_executables = excluded.discovered_executables,
            missing_executables = excluded.missing_executables,
            last_validation_time = excluded.last_validation_time
        "#,
        params![
            encode_state(&status.state),
            status.resolved_install_path,
            serde_json::to_string(&status.discovered_executables)?,
            serde_json::to_string(&status.missing_executables)?,
            status.last_validation_time
        ],
    )?;
    Ok(())
}

fn open_connection(database_path: &str) -> EngineResult<Connection> {
    let connection = Connection::open(database_path)?;
    connection.pragma_update(None, "foreign_keys", "ON")?;
    connection.pragma_update(None, "journal_mode", "WAL")?;
    Ok(connection)
}

fn apply_migrations(connection: &Connection) -> EngineResult<bool> {
    let current_version: i64 =
        connection.pragma_query_value(None, "user_version", |row| row.get(0))?;

    if current_version >= 1 {
        return Ok(false);
    }

    connection.execute_batch(
        r#"
        BEGIN;
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
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS artifacts (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            status TEXT NOT NULL,
            path TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        PRAGMA user_version = 1;
        COMMIT;
        "#,
    )?;

    Ok(true)
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

fn encode_state(state: &ToolchainState) -> &'static str {
    match state {
        ToolchainState::Ready => "ready",
        ToolchainState::Partial => "partial",
        ToolchainState::NotFound => "not_found",
    }
}
