//! Scalar-only quiet exclusion notices.

use rusqlite::{Connection, Transaction, params};

use crate::{Result, StoreError, UnixMillis};

impl NoticeRecord {
    /// Creates a notice after validating its id and positive count.
    pub fn new(
        id: impl Into<String>,
        created_at: UnixMillis,
        count: u64,
        reason: NoticeReason,
    ) -> Result<Self> {
        let id = id.into();
        if id.is_empty() {
            return Err(StoreError::EmptyNoticeId);
        }
        if count == 0 {
            return Err(StoreError::EmptyNoticeCount);
        }
        Ok(Self {
            id,
            created_at,
            count,
            reason,
        })
    }

    /// Returns a one-line, quiet notice that contains only a count and reason.
    pub fn text(&self) -> String {
        let (noun, verb) = if self.count == 1 {
            ("capture", "was")
        } else {
            ("captures", "were")
        };
        format!(
            "{} {noun} {verb} excluded because {}.",
            self.count,
            self.reason.explanation(self.count)
        )
    }
}

impl NoticeReason {
    pub(crate) const fn as_str(self) -> &'static str {
        match self {
            Self::ApplicationExcluded => "application_excluded",
            Self::WindowExcluded => "window_excluded",
        }
    }

    fn explanation(self, count: u64) -> &'static str {
        match (self, count == 1) {
            (Self::ApplicationExcluded, true) => "the application is excluded",
            (Self::ApplicationExcluded, false) => "the applications are excluded",
            (Self::WindowExcluded, true) => "the window is excluded",
            (Self::WindowExcluded, false) => "the windows are excluded",
        }
    }

    fn from_str(value: &str) -> Result<Self> {
        match value {
            "application_excluded" => Ok(Self::ApplicationExcluded),
            "window_excluded" => Ok(Self::WindowExcluded),
            other => Err(StoreError::UnknownNoticeReason(other.to_owned())),
        }
    }
}

/// A compact, durable notice about captures excluded before sealing.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NoticeRecord {
    /// Stable notice identifier.
    pub id: String,
    /// Notice creation time.
    pub created_at: UnixMillis,
    /// Number of captures represented by the notice.
    pub count: u64,
    /// Category explaining why those captures were excluded.
    pub reason: NoticeReason,
}

/// Category used by a quiet exclusion notice.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NoticeReason {
    /// The active application matched an exclusion rule.
    ApplicationExcluded,
    /// The active window matched an exclusion rule.
    WindowExcluded,
}

pub(crate) fn insert(transaction: &Transaction<'_>, record: &NoticeRecord) -> Result<()> {
    let count = i64::try_from(record.count).map_err(|_| StoreError::TimestampOverflow)?;
    transaction.execute(
        "INSERT INTO notices (notice_id, created_at_ms, excluded_count, reason)
         VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT(notice_id) DO UPDATE SET
           created_at_ms = excluded.created_at_ms,
           excluded_count = excluded.excluded_count,
           reason = excluded.reason",
        params![
            record.id,
            record.created_at.as_millis(),
            count,
            record.reason.as_str(),
        ],
    )?;
    Ok(())
}

pub(crate) fn load(connection: &Connection) -> Result<Vec<NoticeRecord>> {
    let mut statement = connection.prepare(
        "SELECT notice_id, created_at_ms, excluded_count, reason
         FROM notices ORDER BY created_at_ms, notice_id",
    )?;
    let rows = statement.query_map([], |row| {
        let id: String = row.get(0)?;
        let created_at = UnixMillis::from_millis(row.get(1)?);
        let count: i64 = row.get(2)?;
        let reason_text: String = row.get(3)?;
        let reason = NoticeReason::from_str(&reason_text).map_err(|error| {
            rusqlite::Error::FromSqlConversionFailure(
                3,
                rusqlite::types::Type::Text,
                Box::new(error),
            )
        })?;
        let count = u64::try_from(count).map_err(|_| {
            rusqlite::Error::FromSqlConversionFailure(
                2,
                rusqlite::types::Type::Integer,
                Box::new(StoreError::EmptyNoticeCount),
            )
        })?;
        Ok(NoticeRecord {
            id,
            created_at,
            count,
            reason,
        })
    })?;
    rows.collect::<std::result::Result<Vec<_>, _>>()
        .map_err(Into::into)
}
