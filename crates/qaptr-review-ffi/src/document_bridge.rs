//! Observation detail, on-demand workflow generation, and Markdown export.
//!
//! These are the three remaining coarse bridge operations beyond the
//! review-session lifecycle in [`crate::driver`]: observation detail, workflow
//! generation, and export. Every request and response here is bounded scalar
//! JSON. No image bytes, credentials, or provider payloads cross this
//! boundary, and no vault or provider type is mirrored; callers get only the
//! same durable [`qaptr_store`] records already exposed by
//! [`crate::qaptr_store_snapshot_json`] plus the pure, deterministic
//! [`qaptr_workflow::WorkflowDocument`] construction and Markdown rendering
//! already used by the review app's local pipeline.
//!
//! Unlike the review-session operations, workflow generation and export are
//! naturally idempotent: generation upserts the same stable workflow id for a
//! given observation, and export atomically overwrites the same
//! caller-chosen destination. Both are therefore safe to execute on the C
//! ABI's ordinary two-pass size/output query without the mutation-replay
//! bookkeeping `qaptr_review_session_json` needs for its non-idempotent
//! session lifecycle.

use std::path::PathBuf;
use std::time::SystemTime;

use qaptr_domain::{ObservationId, WorkflowId};
use qaptr_store::{ObservationRecord, UnixMillis, WorkflowRecord};
use qaptr_workflow::{ExportError, MarkdownExportVariant, NeverCancelled, WorkflowDocument};
use serde_json::{Map, Value, json};

use crate::QaptrStoreHandle;

const VERSION: u64 = 1;
const MALFORMED_REQUEST: &str = "malformed_request";
const STORE_UNAVAILABLE: &str = "store_unavailable";
const OBSERVATION_NOT_FOUND: &str = "observation_not_found";
const WORKFLOW_NOT_FOUND: &str = "workflow_not_found";
const GENERATION_FAILED: &str = "generation_failed";
const PERSIST_FAILED: &str = "persist_failed";
const DECODE_FAILED: &str = "workflow_decode_failed";
const EXPORT_FAILED: &str = "export_failed";
const EXPORT_CANCELLED: &str = "export_cancelled";
const CLOCK_UNAVAILABLE: &str = "clock_unavailable";

/// Maximum accepted request size, matching the review-session boundary.
const MAX_REQUEST_BYTES: usize = 4 * 1024;
/// Maximum accepted scalar identifier length.
const MAX_ID_BYTES: usize = 256;
/// Maximum accepted caller-supplied export destination length.
const MAX_PATH_BYTES: usize = 4 * 1024;

/// Converts one durable observation into the scalar JSON shape shared with
/// [`crate::qaptr_store_snapshot_json`].
pub(crate) fn observation_to_json(observation: &ObservationRecord) -> Value {
    json!({
        "id": observation.id.as_str(),
        "capture_id": observation.capture_id.as_ref().map(qaptr_domain::CaptureId::as_str),
        "session_id": observation.session_id.as_str(),
        "title": observation.title,
        "summary": observation.summary,
        "confidence": observation.confidence.as_f32(),
        "created_at_ms": observation.created_at.as_millis(),
    })
}

/// Converts one durable workflow summary into the scalar JSON shape shared
/// with [`crate::qaptr_store_snapshot_json`].
pub(crate) fn workflow_to_json(workflow: &WorkflowRecord) -> Value {
    json!({
        "id": workflow.id.as_str(),
        "session_id": workflow.session_id.as_str(),
        "title": workflow.title,
        "goal": workflow.goal,
        "context": workflow.context,
        "tools": workflow.tools,
        "sequence": workflow.sequence,
        "decisions": workflow.decisions,
        "variations": workflow.variations,
        "evidence_confidence": workflow.evidence_confidence.as_f32(),
        "created_at_ms": workflow.created_at.as_millis(),
    })
}

fn ok_response(fields: Value) -> Value {
    let mut object = Map::new();
    object.insert("version".to_owned(), json!(VERSION));
    object.insert("ok".to_owned(), json!(true));
    if let Value::Object(extra) = fields {
        object.extend(extra);
    }
    Value::Object(object)
}

fn error_response(error: &'static str) -> Value {
    json!({
        "version": VERSION,
        "ok": false,
        "error": error,
    })
}

fn parse_request(input: &[u8]) -> Result<Map<String, Value>, &'static str> {
    if input.len() > MAX_REQUEST_BYTES {
        return Err(MALFORMED_REQUEST);
    }
    let value: Value = serde_json::from_slice(input).map_err(|_| MALFORMED_REQUEST)?;
    value.as_object().cloned().ok_or(MALFORMED_REQUEST)
}

fn bounded_string(
    object: &Map<String, Value>,
    key: &'static str,
    max_len: usize,
) -> Result<String, &'static str> {
    let value = object
        .get(key)
        .and_then(Value::as_str)
        .ok_or(MALFORMED_REQUEST)?;
    if value.is_empty() || value.len() > max_len {
        return Err(MALFORMED_REQUEST);
    }
    Ok(value.to_owned())
}

fn check_allowed_keys(object: &Map<String, Value>, allowed: &[&str]) -> Result<(), &'static str> {
    for key in object.keys() {
        if !allowed.contains(&key.as_str()) {
            return Err(MALFORMED_REQUEST);
        }
    }
    if object.get("version").and_then(Value::as_u64) != Some(VERSION) {
        return Err(MALFORMED_REQUEST);
    }
    Ok(())
}

/// Handles one bounded JSON v1 observation-detail request.
///
/// The request is `{"version":1,"observation_id":"..."}`. The response
/// contains the same scalar observation fields as the snapshot endpoint, or a
/// terse error when the observation is not found or the store is
/// unavailable.
pub(crate) fn observation_detail(handle: &mut QaptrStoreHandle, request: &[u8]) -> Value {
    let observation_id = match parse_observation_detail_request(request) {
        Ok(id) => id,
        Err(error) => return error_response(error),
    };
    let snapshot = match handle.store.snapshot() {
        Ok(snapshot) => snapshot,
        Err(error) => {
            handle.last_error = error.to_string();
            return error_response(STORE_UNAVAILABLE);
        }
    };
    match snapshot
        .observations
        .into_iter()
        .find(|observation| observation.id == observation_id)
    {
        Some(observation) => {
            ok_response(json!({ "observation": observation_to_json(&observation) }))
        }
        None => error_response(OBSERVATION_NOT_FOUND),
    }
}

fn parse_observation_detail_request(input: &[u8]) -> Result<ObservationId, &'static str> {
    let object = parse_request(input)?;
    check_allowed_keys(&object, &["version", "observation_id"])?;
    let id = bounded_string(&object, "observation_id", MAX_ID_BYTES)?;
    ObservationId::new(id).map_err(|_| MALFORMED_REQUEST)
}

/// Handles one bounded JSON v1 workflow-generation request.
///
/// The request is `{"version":1,"observation_id":"..."}`. Generation builds
/// the canonical [`WorkflowDocument`] from the selected durable observation
/// through [`WorkflowDocument::from_observation`], the same pure conversion
/// the review app's local pipeline already uses, and persists it through the
/// existing [`qaptr_store::Store::put_workflow`] writer. Missing sequence
/// detail stays visibly missing; nothing is inferred. The generated workflow
/// id is stable for a given observation id, so repeating this request
/// replaces the same durable row instead of creating a duplicate.
pub(crate) fn workflow_generate(handle: &mut QaptrStoreHandle, request: &[u8]) -> Value {
    let observation_id = match parse_workflow_generate_request(request) {
        Ok(id) => id,
        Err(error) => return error_response(error),
    };
    let snapshot = match handle.store.snapshot() {
        Ok(snapshot) => snapshot,
        Err(error) => {
            handle.last_error = error.to_string();
            return error_response(STORE_UNAVAILABLE);
        }
    };
    let Some(observation) = snapshot
        .observations
        .into_iter()
        .find(|observation| observation.id == observation_id)
    else {
        return error_response(OBSERVATION_NOT_FOUND);
    };

    let document = match WorkflowDocument::from_observation(&observation) {
        Ok(document) => document,
        Err(error) => {
            handle.last_error = error.to_string();
            return error_response(GENERATION_FAILED);
        }
    };
    let created_at = match UnixMillis::from_system_time(SystemTime::now()) {
        Ok(created_at) => created_at,
        Err(error) => {
            handle.last_error = error.to_string();
            return error_response(CLOCK_UNAVAILABLE);
        }
    };
    let record = match document.to_record(created_at) {
        Ok(record) => record,
        Err(error) => {
            handle.last_error = error.to_string();
            return error_response(GENERATION_FAILED);
        }
    };
    if let Err(error) = handle.store.put_workflow(&record) {
        handle.last_error = error.to_string();
        return error_response(PERSIST_FAILED);
    }
    ok_response(json!({ "workflow": workflow_to_json(&record) }))
}

fn parse_workflow_generate_request(input: &[u8]) -> Result<ObservationId, &'static str> {
    let object = parse_request(input)?;
    check_allowed_keys(&object, &["version", "observation_id"])?;
    let id = bounded_string(&object, "observation_id", MAX_ID_BYTES)?;
    ObservationId::new(id).map_err(|_| MALFORMED_REQUEST)
}

struct ExportRequest {
    workflow_id: WorkflowId,
    variant: MarkdownExportVariant,
    destination: PathBuf,
}

/// Handles one bounded JSON v1 Markdown-export request.
///
/// The request is
/// `{"version":1,"workflow_id":"...","variant":"automation"|"handoff"|"onboarding"|"sop","destination":"..."}`.
/// The destination is a caller-owned path, such as one already chosen through
/// a native save panel; this bridge does not choose a developer path, create
/// parent directories, or launch another app, agent, or automation. Export
/// reuses the durable workflow record's own canonical decoding
/// ([`WorkflowDocument::from_record`]) and the existing pure renderer/atomic
/// writer in `qaptr_workflow::export`.
pub(crate) fn workflow_export(handle: &mut QaptrStoreHandle, request: &[u8]) -> Value {
    let request = match parse_export_request(request) {
        Ok(request) => request,
        Err(error) => return error_response(error),
    };
    let snapshot = match handle.store.snapshot() {
        Ok(snapshot) => snapshot,
        Err(error) => {
            handle.last_error = error.to_string();
            return error_response(STORE_UNAVAILABLE);
        }
    };
    let Some(record) = snapshot
        .workflows
        .into_iter()
        .find(|workflow| workflow.id == request.workflow_id)
    else {
        return error_response(WORKFLOW_NOT_FOUND);
    };
    let document = match WorkflowDocument::from_record(&record) {
        Ok(document) => document,
        Err(error) => {
            handle.last_error = error.to_string();
            return error_response(DECODE_FAILED);
        }
    };
    match qaptr_workflow::save_markdown_export(
        &document,
        request.variant,
        &request.destination,
        &NeverCancelled,
    ) {
        Ok(()) => ok_response(json!({})),
        Err(ExportError::Cancelled) => error_response(EXPORT_CANCELLED),
        Err(error @ ExportError::Write { .. }) => {
            handle.last_error = error.to_string();
            error_response(EXPORT_FAILED)
        }
    }
}

fn parse_export_request(input: &[u8]) -> Result<ExportRequest, &'static str> {
    let object = parse_request(input)?;
    check_allowed_keys(
        &object,
        &["version", "workflow_id", "variant", "destination"],
    )?;
    let workflow_id = bounded_string(&object, "workflow_id", MAX_ID_BYTES)?;
    let workflow_id = WorkflowId::new(workflow_id).map_err(|_| MALFORMED_REQUEST)?;
    let variant = match bounded_string(&object, "variant", MAX_ID_BYTES)?.as_str() {
        "automation" => MarkdownExportVariant::Automation,
        "handoff" => MarkdownExportVariant::Handoff,
        "onboarding" => MarkdownExportVariant::Onboarding,
        "sop" => MarkdownExportVariant::Sop,
        _ => return Err(MALFORMED_REQUEST),
    };
    let destination = bounded_string(&object, "destination", MAX_PATH_BYTES)?;
    Ok(ExportRequest {
        workflow_id,
        variant,
        destination: PathBuf::from(destination),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use qaptr_domain::{CaptureId, Confidence, SessionId};
    use qaptr_store::{CaptureRecord, Store};

    fn open_handle(dir: &std::path::Path) -> Box<QaptrStoreHandle> {
        let store = Store::open(dir.join("history.sqlite3")).expect("store open");
        Box::new(QaptrStoreHandle {
            store,
            last_error: String::new(),
        })
    }

    fn seed_observation(store: &Store) -> ObservationRecord {
        store
            .put_capture(&CaptureRecord {
                id: CaptureId::new("capture-1").expect("capture id"),
                captured_at: UnixMillis::from_millis(1_000),
                vault_record_id: "generation-1/capture-1".to_owned(),
                context_summary: None,
            })
            .expect("capture insert");
        let observation = ObservationRecord {
            id: ObservationId::new("observation-1").expect("observation id"),
            capture_id: Some(CaptureId::new("capture-1").expect("capture id")),
            session_id: SessionId::new("session-1").expect("session id"),
            title: "Reviewed a document".to_owned(),
            summary: "You reviewed a shared document for ten minutes.".to_owned(),
            confidence: Confidence::new(0.72).expect("confidence"),
            created_at: UnixMillis::from_millis(2_000),
        };
        store
            .put_observation(&observation)
            .expect("observation insert");
        observation
    }

    #[test]
    fn observation_detail_returns_scalar_fields_for_a_known_observation() {
        let root = tempfile::tempdir().expect("temp root");
        let mut handle = open_handle(root.path());
        seed_observation(&handle.store);

        let request = br#"{"version":1,"observation_id":"observation-1"}"#;
        let response = observation_detail(&mut handle, request);
        assert_eq!(response["ok"], true);
        assert_eq!(response["observation"]["title"], "Reviewed a document");
        assert_eq!(response["observation"]["confidence"], 0.72_f32 as f64);
        assert!(response.to_string().find("image").is_none());
    }

    #[test]
    fn observation_detail_reports_not_found_for_an_unknown_id() {
        let root = tempfile::tempdir().expect("temp root");
        let mut handle = open_handle(root.path());

        let request = br#"{"version":1,"observation_id":"missing"}"#;
        let response = observation_detail(&mut handle, request);
        assert_eq!(response["ok"], false);
        assert_eq!(response["error"], OBSERVATION_NOT_FOUND);
    }

    #[test]
    fn observation_detail_rejects_unknown_fields_and_wrong_version() {
        let root = tempfile::tempdir().expect("temp root");
        let mut handle = open_handle(root.path());

        let response = observation_detail(
            &mut handle,
            br#"{"version":1,"observation_id":"a","extra":1}"#,
        );
        assert_eq!(response["error"], MALFORMED_REQUEST);

        let response = observation_detail(&mut handle, br#"{"version":2,"observation_id":"a"}"#);
        assert_eq!(response["error"], MALFORMED_REQUEST);
    }

    #[test]
    fn workflow_generate_persists_a_stable_workflow_from_an_observation() {
        let root = tempfile::tempdir().expect("temp root");
        let mut handle = open_handle(root.path());
        seed_observation(&handle.store);

        let request = br#"{"version":1,"observation_id":"observation-1"}"#;
        let response = workflow_generate(&mut handle, request);
        assert_eq!(response["ok"], true);
        assert_eq!(response["workflow"]["title"], "Reviewed a document");
        let workflow_id = response["workflow"]["id"]
            .as_str()
            .expect("workflow id")
            .to_owned();

        let snapshot = handle.store.snapshot().expect("snapshot");
        assert_eq!(snapshot.workflows.len(), 1);
        assert_eq!(snapshot.workflows[0].id.as_str(), workflow_id);

        // Regenerating from the same observation replaces the same row rather
        // than creating a duplicate.
        let second = workflow_generate(&mut handle, request);
        assert_eq!(second["ok"], true);
        assert_eq!(second["workflow"]["id"], workflow_id);
        let snapshot = handle.store.snapshot().expect("snapshot");
        assert_eq!(snapshot.workflows.len(), 1);
    }

    #[test]
    fn workflow_generate_reports_not_found_for_an_unknown_observation() {
        let root = tempfile::tempdir().expect("temp root");
        let mut handle = open_handle(root.path());

        let request = br#"{"version":1,"observation_id":"missing"}"#;
        let response = workflow_generate(&mut handle, request);
        assert_eq!(response["ok"], false);
        assert_eq!(response["error"], OBSERVATION_NOT_FOUND);
    }

    #[test]
    fn workflow_export_writes_a_variant_and_reports_not_found_for_unknown_ids() {
        let root = tempfile::tempdir().expect("temp root");
        let mut handle = open_handle(root.path());
        seed_observation(&handle.store);
        let generated = workflow_generate(
            &mut handle,
            br#"{"version":1,"observation_id":"observation-1"}"#,
        );
        let workflow_id = generated["workflow"]["id"]
            .as_str()
            .expect("workflow id")
            .to_owned();

        let destination = root.path().join("export.md");
        let request = format!(
            r#"{{"version":1,"workflow_id":"{workflow_id}","variant":"sop","destination":"{}"}}"#,
            destination.to_string_lossy()
        );
        let response = workflow_export(&mut handle, request.as_bytes());
        assert_eq!(response["ok"], true);
        let written = std::fs::read_to_string(&destination).expect("exported markdown");
        assert!(written.contains("Standard Operating Procedure"));

        let missing_request = format!(
            r#"{{"version":1,"workflow_id":"does-not-exist","variant":"sop","destination":"{}"}}"#,
            destination.to_string_lossy()
        );
        let response = workflow_export(&mut handle, missing_request.as_bytes());
        assert_eq!(response["ok"], false);
        assert_eq!(response["error"], WORKFLOW_NOT_FOUND);
    }

    #[test]
    fn workflow_export_rejects_an_unknown_variant() {
        let root = tempfile::tempdir().expect("temp root");
        let mut handle = open_handle(root.path());
        seed_observation(&handle.store);
        let generated = workflow_generate(
            &mut handle,
            br#"{"version":1,"observation_id":"observation-1"}"#,
        );
        let workflow_id = generated["workflow"]["id"]
            .as_str()
            .expect("workflow id")
            .to_owned();

        let destination = root.path().join("export.md");
        let request = format!(
            r#"{{"version":1,"workflow_id":"{workflow_id}","variant":"unsupported","destination":"{}"}}"#,
            destination.to_string_lossy()
        );
        let response = workflow_export(&mut handle, request.as_bytes());
        assert_eq!(response["error"], MALFORMED_REQUEST);
        assert!(!destination.exists());
    }
}
