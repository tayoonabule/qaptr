//! Allowlisted schema validation for the durable history database.

use std::collections::BTreeSet;

use rusqlite::Connection;

use crate::{Result, StoreError};

const TABLE_COLUMNS: &[(&str, &[&str])] = &[
    (
        "captures",
        &[
            "capture_id",
            "captured_at_ms",
            "vault_record_id",
            "context_summary",
        ],
    ),
    (
        "observations",
        &[
            "observation_id",
            "capture_id",
            "session_id",
            "title",
            "summary",
            "confidence",
            "created_at_ms",
        ],
    ),
    (
        "workflows",
        &[
            "workflow_id",
            "session_id",
            "title",
            "goal",
            "context",
            "tools",
            "sequence",
            "decisions",
            "variations",
            "evidence_confidence",
            "created_at_ms",
        ],
    ),
];

const FORBIDDEN_NAME_PARTS: &[&str] = &[
    "blob",
    "image",
    "photo",
    "picture",
    "screenshot",
    "thumbnail",
    "bitmap",
];

/// Validates that the database contains only the history schema and scalar columns.
pub(crate) fn validate(connection: &Connection) -> Result<()> {
    let mut statement = connection.prepare(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    )?;
    let actual_tables = statement
        .query_map([], |row| row.get::<_, String>(0))?
        .collect::<std::result::Result<BTreeSet<_>, _>>()?;
    let expected_tables = TABLE_COLUMNS
        .iter()
        .map(|(table, _)| (*table).to_owned())
        .collect::<BTreeSet<_>>();
    if actual_tables != expected_tables {
        return Err(StoreError::InvalidSchema {
            reason: format!(
                "tables are not allowlisted: expected {expected_tables:?}, found {actual_tables:?}"
            ),
        });
    }

    for &(table, expected_columns) in TABLE_COLUMNS {
        validate_table(connection, table, expected_columns)?;
    }
    Ok(())
}

fn validate_table(connection: &Connection, table: &str, expected_columns: &[&str]) -> Result<()> {
    if has_forbidden_name_part(table) {
        return Err(StoreError::InvalidSchema {
            reason: format!("image-like table name is not allowed: {table}"),
        });
    }

    let query = format!("PRAGMA table_info('{table}')");
    let mut statement = connection.prepare(&query)?;
    let mut actual_columns = BTreeSet::new();
    let rows = statement.query_map([], |row| {
        Ok((row.get::<_, String>(1)?, row.get::<_, String>(2)?))
    })?;
    for row in rows {
        let (name, declared_type) = row?;
        if has_forbidden_name_part(&name) {
            return Err(StoreError::InvalidSchema {
                reason: format!("image-like column name is not allowed: {table}.{name}"),
            });
        }
        let normalized_type = declared_type.trim().to_ascii_uppercase();
        if normalized_type.contains("BLOB")
            || !matches!(normalized_type.as_str(), "TEXT" | "INTEGER" | "REAL")
        {
            return Err(StoreError::InvalidSchema {
                reason: format!(
                    "column {table}.{name} has a non-scalar or blob type: {declared_type}"
                ),
            });
        }
        actual_columns.insert(name);
    }

    let expected_columns = expected_columns
        .iter()
        .map(|column| (*column).to_owned())
        .collect::<BTreeSet<_>>();
    if actual_columns != expected_columns {
        return Err(StoreError::InvalidSchema {
            reason: format!(
                "columns for {table} are not allowlisted: expected {expected_columns:?}, found {actual_columns:?}"
            ),
        });
    }
    Ok(())
}

fn has_forbidden_name_part(name: &str) -> bool {
    let normalized = name.to_ascii_lowercase();
    FORBIDDEN_NAME_PARTS
        .iter()
        .any(|part| normalized.contains(part))
}

#[cfg(test)]
mod tests {
    use rusqlite::Connection;

    use super::validate;

    fn valid_connection() -> Connection {
        let connection = Connection::open_in_memory().expect("in-memory SQLite must open");
        connection
            .execute_batch(include_str!("migrations/0001_initial.sql"))
            .expect("the production schema must execute");
        connection
    }

    #[test]
    fn rejects_blob_columns() {
        let connection = valid_connection();
        connection
            .execute("ALTER TABLE captures ADD COLUMN debug_blob BLOB", [])
            .expect("the mutation must be accepted by raw SQLite");
        assert!(validate(&connection).is_err());
    }

    #[test]
    fn rejects_image_like_tables() {
        let connection = valid_connection();
        connection
            .execute("CREATE TABLE image_cache (record TEXT)", [])
            .expect("the mutation must be accepted by raw SQLite");
        assert!(validate(&connection).is_err());
    }
}
