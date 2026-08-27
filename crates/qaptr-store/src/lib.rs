//! Durable scalar SQLite history for Qaptr.
//!
//! # Invariants
//!
//! - This crate is the sole writer owner of the history database inside the
//!   review-app process. It never opens a capture vault and never writes image
//!   bytes, thumbnails, screenshots, or other image material. Its allowlisted
//!   schema has no binary columns, and every writer rejects text values that
//!   look like encoded image material. This is a writer invariant, not a claim
//!   that an external actor with raw SQLite access cannot bypass the API.
//! - SQLite is always opened in WAL mode using the bundled SQLite build. The
//!   bundled build must be new enough to contain the 2026 WAL-reset corruption
//!   fix, currently SQLite 3.53.2 through `rusqlite` 0.40.2.
//! - The public API writes only compact scalar summaries. The allowlisted schema
//!   validator rejects unknown tables, image-like names, blob columns, and
//!   non-scalar declared column types.
//! - Capture deletion is intentionally non-cascading for durable observations
//!   and workflows. Their source capture reference becomes absent while the
//!   summaries remain available.

mod history;
mod material;
mod migrations;
mod notices;
mod schema;

use std::{
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::Duration,
};

use history::load_snapshot;
use rusqlite::{Connection, OpenFlags};
use thiserror::Error;

/// SQLite release containing the WAL-reset fix required by KTD5.
pub const MINIMUM_SQLITE_VERSION: (u32, u32, u32) = (3, 51, 3);

/// Errors returned by the durable history repository.
#[derive(Debug, Error)]
pub enum StoreError {
    /// SQLite returned an error.
    #[error("sqlite error: {0}")]
    Database(#[from] rusqlite::Error),
    /// Filesystem access failed while opening the database.
    #[error("database filesystem error: {0}")]
    Filesystem(#[from] std::io::Error),
    /// A writer lock was poisoned after a prior panic.
    #[error("the single-writer lock is poisoned")]
    WriterPoisoned,
    /// The database schema is not the allowlisted scalar history schema.
    #[error("invalid qaptr-store schema: {reason}")]
    InvalidSchema {
        /// Explanation of the rejected schema.
        reason: String,
    },
    /// The database was created by a newer migration set.
    #[error("database schema version {current} is newer than supported version {latest}")]
    UnknownSchemaVersion {
        /// Version found in SQLite.
        current: i64,
        /// Newest version understood by this crate.
        latest: i64,
    },
    /// SQLite is too old to safely use WAL mode for this crate.
    #[error("SQLite {found} is too old; qaptr-store requires at least {required}")]
    SqliteTooOld {
        /// Runtime SQLite version.
        found: String,
        /// Minimum safe SQLite version.
        required: String,
    },
    /// A timestamp was before the Unix epoch.
    #[error("timestamp is before the Unix epoch: {source}")]
    InvalidTimestamp {
        /// Standard-library conversion error.
        source: std::time::SystemTimeError,
    },
    /// A timestamp cannot fit in the database integer representation.
    #[error("timestamp is too large for SQLite's integer representation")]
    TimestampOverflow,
    /// A notice id was empty.
    #[error("notice id must not be empty")]
    EmptyNoticeId,
    /// A notice count was zero.
    #[error("notice count must be greater than zero")]
    EmptyNoticeCount,
    /// A text value looks like encoded or raw image material.
    #[error("text field {field} appears to contain encoded image material")]
    EncodedImageMaterial {
        /// The logical field being rejected.
        field: String,
    },
    /// A stored notice reason was not recognized.
    #[error("unknown notice reason: {0}")]
    UnknownNoticeReason(String),
}

/// Convenient result type for qaptr-store operations.
pub type Result<T> = std::result::Result<T, StoreError>;

/// A single-writer repository backed by a file on disk.
#[derive(Clone)]
pub struct Store {
    path: Arc<PathBuf>,
    writer: Arc<Mutex<Connection>>,
}

impl Store {
    /// Opens or creates a history database, applies forward migrations, and
    /// configures bundled SQLite for WAL mode.
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref().to_path_buf();
        let mut connection = Connection::open(&path)?;
        configure_writer(&mut connection)?;
        migrations::apply(&mut connection)?;
        schema::validate(&connection)?;
        Ok(Self {
            path: Arc::new(path),
            writer: Arc::new(Mutex::new(connection)),
        })
    }

    /// Returns the compiled migration version.
    pub const fn schema_version() -> i64 {
        migrations::latest_version()
    }

    /// Returns the runtime SQLite version used by this repository.
    pub fn sqlite_version(&self) -> Result<String> {
        let writer = self.writer.lock().map_err(|_| StoreError::WriterPoisoned)?;
        sqlite_version(&writer)
    }

    /// Runs a write transaction owned by this repository's single writer.
    pub fn transaction<T>(
        &self,
        operation: impl FnOnce(&mut WriteTransaction<'_>) -> Result<T>,
    ) -> Result<T> {
        let mut writer = self.writer.lock().map_err(|_| StoreError::WriterPoisoned)?;
        let transaction = writer.transaction()?;
        let mut batch = WriteTransaction::new(transaction);
        match operation(&mut batch) {
            Ok(result) => {
                batch.into_transaction().commit()?;
                Ok(result)
            }
            Err(error) => Err(error),
        }
    }

    /// Stores capture metadata without storing capture bytes; encoded image
    /// material in scalar text fields is rejected before the SQL write.
    pub fn put_capture(&self, record: &CaptureRecord) -> Result<()> {
        self.transaction(|transaction| transaction.put_capture(record))
    }

    /// Stores a compact observation summary after text-material validation.
    pub fn put_observation(&self, record: &ObservationRecord) -> Result<()> {
        self.transaction(|transaction| transaction.put_observation(record))
    }

    /// Stores a canonical workflow summary after text-material validation.
    pub fn put_workflow(&self, record: &WorkflowRecord) -> Result<()> {
        self.transaction(|transaction| transaction.put_workflow(record))
    }

    /// Stores one compact exclusion notice without capture content.
    pub fn put_notice(&self, record: &NoticeRecord) -> Result<()> {
        self.transaction(|transaction| transaction.put_notice(record))
    }

    /// Returns compact exclusion notices in creation order.
    pub fn notices(&self) -> Result<Vec<NoticeRecord>> {
        let writer = self.writer.lock().map_err(|_| StoreError::WriterPoisoned)?;
        notices::load(&writer)
    }

    /// Deletes one capture's vault metadata while preserving dependent history.
    pub fn delete_capture(&self, capture_id: &qaptr_domain::CaptureId) -> Result<bool> {
        let writer = self.writer.lock().map_err(|_| StoreError::WriterPoisoned)?;
        let deleted = writer.execute(
            "DELETE FROM captures WHERE capture_id = ?1",
            [capture_id.as_str()],
        )?;
        Ok(deleted == 1)
    }

    /// Deletes several capture metadata rows in one transaction while leaving
    /// observations and workflows intact.
    pub fn delete_captures(&self, capture_ids: &[qaptr_domain::CaptureId]) -> Result<usize> {
        self.transaction(|transaction| transaction.delete_captures(capture_ids))
    }

    /// Reads a transactionally consistent snapshot using a separate reader.
    pub fn snapshot(&self) -> Result<HistorySnapshot> {
        let mut reader = open_reader(&self.path)?;
        load_snapshot(&mut reader)
    }

    /// Verifies the live schema against the binary-free scalar allowlist.
    pub fn verify_schema(&self) -> Result<()> {
        let writer = self.writer.lock().map_err(|_| StoreError::WriterPoisoned)?;
        schema::validate(&writer)
    }

    /// Runs SQLite's integrity check after an interrupted or crashed write.
    pub fn integrity_check(&self) -> Result<()> {
        let writer = self.writer.lock().map_err(|_| StoreError::WriterPoisoned)?;
        let result: String = writer.query_row("PRAGMA integrity_check", [], |row| row.get(0))?;
        if result == "ok" {
            Ok(())
        } else {
            Err(StoreError::InvalidSchema {
                reason: format!("SQLite integrity check failed: {result}"),
            })
        }
    }
}

fn configure_writer(connection: &mut Connection) -> Result<()> {
    connection.busy_timeout(Duration::from_secs(5))?;
    connection.execute_batch("PRAGMA foreign_keys = ON; PRAGMA synchronous = NORMAL;")?;
    let mode: String = connection.query_row("PRAGMA journal_mode = WAL", [], |row| row.get(0))?;
    if mode.eq_ignore_ascii_case("wal") {
        validate_sqlite_version(connection)
    } else {
        Err(StoreError::InvalidSchema {
            reason: format!("SQLite journal mode is {mode}, not WAL"),
        })
    }
}

fn open_reader(path: &Path) -> Result<Connection> {
    let flags = OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_FULL_MUTEX;
    let connection = Connection::open_with_flags(path, flags)?;
    connection.busy_timeout(Duration::from_secs(5))?;
    connection.execute_batch("PRAGMA query_only = ON; PRAGMA foreign_keys = ON;")?;
    let mode: String = connection.query_row("PRAGMA journal_mode", [], |row| row.get(0))?;
    if !mode.eq_ignore_ascii_case("wal") {
        return Err(StoreError::InvalidSchema {
            reason: format!("reader observed SQLite journal mode {mode}, not WAL"),
        });
    }
    validate_sqlite_version(&connection)?;
    schema::validate(&connection)?;
    Ok(connection)
}

fn validate_sqlite_version(connection: &Connection) -> Result<()> {
    let version = sqlite_version(connection)?;
    let parsed = version
        .split('.')
        .take(3)
        .map(|part| part.parse::<u32>())
        .collect::<std::result::Result<Vec<_>, _>>()
        .map_err(|_| StoreError::SqliteTooOld {
            found: version.clone(),
            required: version_string(MINIMUM_SQLITE_VERSION),
        })?;
    if parsed.len() < 3 {
        return Err(StoreError::SqliteTooOld {
            found: version,
            required: version_string(MINIMUM_SQLITE_VERSION),
        });
    }
    let actual = (parsed[0], parsed[1], parsed[2]);
    if actual < MINIMUM_SQLITE_VERSION {
        return Err(StoreError::SqliteTooOld {
            found: version,
            required: version_string(MINIMUM_SQLITE_VERSION),
        });
    }
    Ok(())
}

fn sqlite_version(connection: &Connection) -> Result<String> {
    Ok(connection.query_row("SELECT sqlite_version()", [], |row| row.get(0))?)
}

fn version_string(version: (u32, u32, u32)) -> String {
    format!("{}.{}.{}", version.0, version.1, version.2)
}

pub use history::{
    CaptureRecord, HistorySnapshot, ObservationRecord, UnixMillis, WorkflowRecord, WriteTransaction,
};
pub use notices::{NoticeReason, NoticeRecord};
