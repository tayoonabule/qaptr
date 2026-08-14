//! Forward-only database migrations.

use rusqlite::Connection;

use crate::{Result, StoreError};

const MIGRATIONS: &[(i64, &str)] = &[(1, include_str!("0001_initial.sql"))];

/// Applies every migration newer than the database's current user version.
pub(crate) fn apply(connection: &mut Connection) -> Result<()> {
    let current: i64 = connection.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    let latest = MIGRATIONS.last().map_or(0, |(version, _)| *version);
    if current > latest {
        return Err(StoreError::UnknownSchemaVersion { current, latest });
    }

    for &(version, sql) in MIGRATIONS.iter().filter(|(version, _)| *version > current) {
        let transaction = connection.transaction()?;
        transaction.execute_batch(sql)?;
        transaction.execute_batch(&format!("PRAGMA user_version = {version}"))?;
        transaction.commit()?;
    }
    Ok(())
}

/// Returns the newest migration version compiled into this crate.
pub(crate) const fn latest_version() -> i64 {
    1
}
