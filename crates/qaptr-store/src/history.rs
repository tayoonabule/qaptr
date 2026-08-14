//! Typed records and the narrow history repository API.

use std::time::{SystemTime, UNIX_EPOCH};

use qaptr_domain::{CaptureId, Confidence, ObservationId, SessionId, WorkflowId};
use rusqlite::{Connection, Transaction, params};

use crate::{Result, StoreError};

/// A signed count of milliseconds since the Unix epoch.
#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub struct UnixMillis(i64);

impl UnixMillis {
    /// Creates a timestamp from milliseconds since the Unix epoch.
    pub const fn from_millis(value: i64) -> Self {
        Self(value)
    }

    /// Converts a system time into milliseconds since the Unix epoch.
    pub fn from_system_time(value: SystemTime) -> Result<Self> {
        let duration = value
            .duration_since(UNIX_EPOCH)
            .map_err(|source| StoreError::InvalidTimestamp { source })?;
        let millis =
            i64::try_from(duration.as_millis()).map_err(|_| StoreError::TimestampOverflow)?;
        Ok(Self(millis))
    }

    /// Returns milliseconds since the Unix epoch.
    pub const fn as_millis(self) -> i64 {
        self.0
    }
}

/// Durable metadata for one capture bundle in the vault.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CaptureRecord {
    /// Stable capture identifier.
    pub id: CaptureId,
    /// Capture time.
    pub captured_at: UnixMillis,
    /// Opaque vault record identifier. This is not image data or a file payload.
    pub vault_record_id: String,
    /// Optional compact context summary.
    pub context_summary: Option<String>,
}

/// A compact observation derived from one or more captures.
#[derive(Clone, Debug, PartialEq)]
pub struct ObservationRecord {
    /// Stable observation identifier.
    pub id: ObservationId,
    /// Source capture, if the vault record still exists.
    pub capture_id: Option<CaptureId>,
    /// Analysis session identifier.
    pub session_id: SessionId,
    /// Short observation title.
    pub title: String,
    /// Human-readable observation summary.
    pub summary: String,
    /// Evidence confidence in the inclusive range from zero to one.
    pub confidence: Confidence,
    /// Observation creation time.
    pub created_at: UnixMillis,
}

/// A canonical workflow summary stored without source images.
#[derive(Clone, Debug, PartialEq)]
pub struct WorkflowRecord {
    /// Stable workflow identifier.
    pub id: WorkflowId,
    /// Analysis session identifier.
    pub session_id: SessionId,
    /// Workflow title.
    pub title: String,
    /// Workflow goal.
    pub goal: String,
    /// Workflow context.
    pub context: String,
    /// Tools used by the workflow.
    pub tools: String,
    /// Ordered workflow sequence.
    pub sequence: String,
    /// Decisions made in the workflow.
    pub decisions: String,
    /// Known workflow variations.
    pub variations: String,
    /// Confidence in the workflow evidence.
    pub evidence_confidence: Confidence,
    /// Workflow creation time.
    pub created_at: UnixMillis,
}

/// A point-in-time, internally consistent view of durable history.
#[derive(Clone, Debug, PartialEq)]
pub struct HistorySnapshot {
    /// Capture metadata present when the snapshot began.
    pub captures: Vec<CaptureRecord>,
    /// Observations present when the snapshot began.
    pub observations: Vec<ObservationRecord>,
    /// Workflows present when the snapshot began.
    pub workflows: Vec<WorkflowRecord>,
}

/// A single-writer transaction over the history repository.
pub struct WriteTransaction<'transaction> {
    transaction: Transaction<'transaction>,
}

impl<'transaction> WriteTransaction<'transaction> {
    pub(crate) const fn new(transaction: Transaction<'transaction>) -> Self {
        Self { transaction }
    }

    /// Inserts or replaces capture metadata, never image bytes.
    pub fn put_capture(&mut self, record: &CaptureRecord) -> Result<()> {
        self.transaction.execute(
            "INSERT INTO captures
             (capture_id, captured_at_ms, vault_record_id, context_summary)
             VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(capture_id) DO UPDATE SET
               captured_at_ms = excluded.captured_at_ms,
               vault_record_id = excluded.vault_record_id,
               context_summary = excluded.context_summary",
            params![
                record.id.as_str(),
                record.captured_at.as_millis(),
                record.vault_record_id,
                record.context_summary,
            ],
        )?;
        Ok(())
    }

    /// Inserts or replaces an observation summary.
    pub fn put_observation(&mut self, record: &ObservationRecord) -> Result<()> {
        self.transaction.execute(
            "INSERT INTO observations
             (observation_id, capture_id, session_id, title, summary, confidence, created_at_ms)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
             ON CONFLICT(observation_id) DO UPDATE SET
               capture_id = excluded.capture_id,
               session_id = excluded.session_id,
               title = excluded.title,
               summary = excluded.summary,
               confidence = excluded.confidence,
               created_at_ms = excluded.created_at_ms",
            params![
                record.id.as_str(),
                record.capture_id.as_ref().map(CaptureId::as_str),
                record.session_id.as_str(),
                record.title,
                record.summary,
                f64::from(record.confidence.as_f32()),
                record.created_at.as_millis(),
            ],
        )?;
        Ok(())
    }

    /// Inserts or replaces a workflow summary without source images.
    pub fn put_workflow(&mut self, record: &WorkflowRecord) -> Result<()> {
        self.transaction.execute(
            "INSERT INTO workflows
             (workflow_id, session_id, title, goal, context, tools, sequence,
              decisions, variations, evidence_confidence, created_at_ms)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
             ON CONFLICT(workflow_id) DO UPDATE SET
               session_id = excluded.session_id,
               title = excluded.title,
               goal = excluded.goal,
               context = excluded.context,
               tools = excluded.tools,
               sequence = excluded.sequence,
               decisions = excluded.decisions,
               variations = excluded.variations,
               evidence_confidence = excluded.evidence_confidence,
               created_at_ms = excluded.created_at_ms",
            params![
                record.id.as_str(),
                record.session_id.as_str(),
                record.title,
                record.goal,
                record.context,
                record.tools,
                record.sequence,
                record.decisions,
                record.variations,
                f64::from(record.evidence_confidence.as_f32()),
                record.created_at.as_millis(),
            ],
        )?;
        Ok(())
    }

    /// Inserts or replaces a compact exclusion notice.
    pub fn put_notice(&mut self, record: &crate::NoticeRecord) -> Result<()> {
        crate::notices::insert(&self.transaction, record)
    }

    /// Deletes capture metadata rows without cascading into derived history.
    pub fn delete_captures(&mut self, capture_ids: &[CaptureId]) -> Result<usize> {
        let mut deleted = 0;
        for capture_id in capture_ids {
            deleted += self.transaction.execute(
                "DELETE FROM captures WHERE capture_id = ?1",
                [capture_id.as_str()],
            )?;
        }
        Ok(deleted)
    }

    pub(crate) fn into_transaction(self) -> Transaction<'transaction> {
        self.transaction
    }
}

pub(crate) fn load_snapshot(connection: &mut Connection) -> Result<HistorySnapshot> {
    let transaction = connection.transaction()?;
    let captures = load_captures(&transaction)?;
    let observations = load_observations(&transaction)?;
    let workflows = load_workflows(&transaction)?;
    transaction.commit()?;
    Ok(HistorySnapshot {
        captures,
        observations,
        workflows,
    })
}

fn load_captures(connection: &Connection) -> Result<Vec<CaptureRecord>> {
    let mut statement = connection.prepare(
        "SELECT capture_id, captured_at_ms, vault_record_id, context_summary
         FROM captures ORDER BY captured_at_ms, capture_id",
    )?;
    let rows = statement.query_map([], |row| {
        Ok(CaptureRecord {
            id: row.get::<_, String>(0)?.parse().map_err(|error| {
                rusqlite::Error::FromSqlConversionFailure(
                    0,
                    rusqlite::types::Type::Text,
                    Box::new(error),
                )
            })?,
            captured_at: UnixMillis::from_millis(row.get(1)?),
            vault_record_id: row.get(2)?,
            context_summary: row.get(3)?,
        })
    })?;
    rows.collect::<std::result::Result<Vec<_>, _>>()
        .map_err(Into::into)
}

fn load_observations(connection: &Connection) -> Result<Vec<ObservationRecord>> {
    let mut statement = connection.prepare(
        "SELECT observation_id, capture_id, session_id, title, summary, confidence, created_at_ms
         FROM observations ORDER BY created_at_ms, observation_id",
    )?;
    let rows = statement.query_map([], |row| {
        let confidence: f64 = row.get(5)?;
        let confidence = Confidence::new(confidence as f32).map_err(|error| {
            rusqlite::Error::FromSqlConversionFailure(
                5,
                rusqlite::types::Type::Real,
                Box::new(error),
            )
        })?;
        Ok(ObservationRecord {
            id: row.get::<_, String>(0)?.parse().map_err(|error| {
                rusqlite::Error::FromSqlConversionFailure(
                    0,
                    rusqlite::types::Type::Text,
                    Box::new(error),
                )
            })?,
            capture_id: row
                .get::<_, Option<String>>(1)?
                .map(|value| value.parse())
                .transpose()
                .map_err(|error| {
                    rusqlite::Error::FromSqlConversionFailure(
                        1,
                        rusqlite::types::Type::Text,
                        Box::new(error),
                    )
                })?,
            session_id: row.get::<_, String>(2)?.parse().map_err(|error| {
                rusqlite::Error::FromSqlConversionFailure(
                    2,
                    rusqlite::types::Type::Text,
                    Box::new(error),
                )
            })?,
            title: row.get(3)?,
            summary: row.get(4)?,
            confidence,
            created_at: UnixMillis::from_millis(row.get(6)?),
        })
    })?;
    rows.collect::<std::result::Result<Vec<_>, _>>()
        .map_err(Into::into)
}

fn load_workflows(connection: &Connection) -> Result<Vec<WorkflowRecord>> {
    let mut statement = connection.prepare(
        "SELECT workflow_id, session_id, title, goal, context, tools, sequence,
                decisions, variations, evidence_confidence, created_at_ms
         FROM workflows ORDER BY created_at_ms, workflow_id",
    )?;
    let rows = statement.query_map([], |row| {
        let evidence_confidence: f64 = row.get(9)?;
        let evidence_confidence = Confidence::new(evidence_confidence as f32).map_err(|error| {
            rusqlite::Error::FromSqlConversionFailure(
                9,
                rusqlite::types::Type::Real,
                Box::new(error),
            )
        })?;
        Ok(WorkflowRecord {
            id: row.get::<_, String>(0)?.parse().map_err(|error| {
                rusqlite::Error::FromSqlConversionFailure(
                    0,
                    rusqlite::types::Type::Text,
                    Box::new(error),
                )
            })?,
            session_id: row.get::<_, String>(1)?.parse().map_err(|error| {
                rusqlite::Error::FromSqlConversionFailure(
                    1,
                    rusqlite::types::Type::Text,
                    Box::new(error),
                )
            })?,
            title: row.get(2)?,
            goal: row.get(3)?,
            context: row.get(4)?,
            tools: row.get(5)?,
            sequence: row.get(6)?,
            decisions: row.get(7)?,
            variations: row.get(8)?,
            evidence_confidence,
            created_at: UnixMillis::from_millis(row.get(10)?),
        })
    })?;
    rows.collect::<std::result::Result<Vec<_>, _>>()
        .map_err(Into::into)
}
