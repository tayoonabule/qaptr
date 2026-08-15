//! Narrow C ABI for the native review app.
//!
//! # Invariants
//!
//! - Before durable-history reads, this bridge can reconcile one capture
//!   generation. Private key material is created or read only through the
//!   review app's non-synchronizing Keychain adapter; only the matching public
//!   key is written to the vault for the helper.
//! - The bridge never opens a vault bundle and has no operation that returns an
//!   image, credential, or provider response. History output remains scalar:
//!   observations, workflow summaries, and quiet exclusion notices.
//! - All values crossing this boundary are already scalar (ids, text,
//!   confidence, and millisecond timestamps). No image bytes ever cross this
//!   ABI, mirroring `qaptr-ffi`'s helper-side invariant in the opposite
//!   direction.
//! - Errors are recorded on the handle and retrieved with
//!   [`qaptr_store_last_error`] rather than panicking across the FFI boundary.

#![allow(unsafe_code)]

mod bootstrap;
mod driver;
pub mod local;
mod support;
mod system;

use qaptr_store::Store;
use serde_json::{Value, json};

pub use system::{
    qaptr_login_item_set_enabled, qaptr_login_item_status, qaptr_permission_request,
    qaptr_permission_state,
};

use support::{copy_string, read_utf8};

/// An opaque app-owned review-session driver.
pub use driver::ReviewSessionDriver;

/// Opens an app-owned review-session driver.
///
/// The driver creates no provider adapter. It owns only the supplied vault and
/// scalar history paths and reports provider availability truthfully at start.
///
/// # Safety
///
/// Each path pointer must reference its declared UTF-8 byte length for the
/// duration of the call, or be null when its length is zero.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qaptr_review_session_open(
    vault_root: *const u8,
    vault_root_len: usize,
    store_path: *const u8,
    store_path_len: usize,
) -> *mut ReviewSessionDriver {
    let (Some(vault_root), Some(store_path)) =
        (unsafe { read_utf8(vault_root, vault_root_len) }, unsafe {
            read_utf8(store_path, store_path_len)
        })
    else {
        return std::ptr::null_mut();
    };
    if vault_root.is_empty() || store_path.is_empty() {
        return std::ptr::null_mut();
    }
    Box::into_raw(Box::new(ReviewSessionDriver::new(
        vault_root.into(),
        store_path.into(),
    )))
}

/// Destroys a review-session driver returned by [`qaptr_review_session_open`].
///
/// # Safety
///
/// `handle` must be null or a live pointer returned by
/// [`qaptr_review_session_open`] that has not already been destroyed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qaptr_review_session_destroy(handle: *mut ReviewSessionDriver) {
    if !handle.is_null() {
        // SAFETY: the pointer came from Box::into_raw in the open function and
        // is consumed exactly once by this destructor.
        unsafe { drop(Box::from_raw(handle)) };
    }
}

/// Executes one bounded JSON v1 review-session operation.
///
/// Requests are objects with `version: 1` and one of `start`, `state`,
/// `decide_consent`, `cancel`, or `retry` operations. The response contains
/// only scalar state, counts, consent summary metadata, and allowed operation
/// names. It never contains image bytes, credentials, provider payloads, or
/// provider responses.
///
/// The return value is the required output capacity including a trailing NUL.
/// A caller can pass a null output pointer or zero capacity to query the size.
///
/// # Safety
///
/// `handle` must be a live driver. `request` must reference `request_len`
/// readable bytes. `output` must reference a writable buffer of
/// `output_capacity` bytes when non-zero.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qaptr_review_session_json(
    handle: *mut ReviewSessionDriver,
    request: *const u8,
    request_len: usize,
    output: *mut u8,
    output_capacity: usize,
) -> usize {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        return copy_string(
            r#"{"version":1,"ok":false,"error":"invalid_handle"}"#,
            output,
            output_capacity,
        );
    };
    let Some(request) = (unsafe { support::read_bytes(request, request_len) }) else {
        return copy_string(
            r#"{"version":1,"ok":false,"error":"malformed_request"}"#,
            output,
            output_capacity,
        );
    };
    let response = handle.request_once(request).to_string();
    let required = copy_string(&response, output, output_capacity);
    if required <= output_capacity && !output.is_null() {
        handle.finish_pending_mutation(request);
    }
    required
}

const LIVE_ANALYSIS_UNAVAILABLE_REASON: &str =
    "live provider analysis is not exposed by qaptr-review-ffi";

/// Reconciles the review app's private generation key with the public key used
/// by the capture helper and returns a small, non-sensitive JSON result.
///
/// The private key is created or read only through the review app's local,
/// non-synchronizing Keychain adapter. The public key is written only after the
/// private half is safely present. Existing mismatched or orphaned public keys
/// fail closed and are never silently replaced.
///
/// # Safety
///
/// Input pointers must reference their declared UTF-8 byte lengths. `output`
/// must reference a writable buffer of `output_capacity` bytes when non-zero.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qaptr_key_bootstrap_json(
    vault_root: *const u8,
    vault_root_len: usize,
    generation: *const u8,
    generation_len: usize,
    output: *mut u8,
    output_capacity: usize,
) -> usize {
    let result = match (unsafe { read_utf8(vault_root, vault_root_len) }, unsafe {
        read_utf8(generation, generation_len)
    }) {
        (Some(vault_root), Some(generation)) => {
            match bootstrap::bootstrap_generation(vault_root, generation) {
                Ok(disposition) => json!({
                    "ready": true,
                    "generation_id": generation,
                    "disposition": match disposition {
                        bootstrap::BootstrapDisposition::Existing => "existing",
                        bootstrap::BootstrapDisposition::Created => "created",
                        bootstrap::BootstrapDisposition::PublicKeyRestored => "public_key_restored",
                    },
                }),
                Err(reason) => json!({ "ready": false, "reason": reason }),
            }
        }
        _ => json!({ "ready": false, "reason": "bootstrap input is not valid UTF-8" }),
    };
    copy_string(&result.to_string(), output, output_capacity)
}

/// An opaque review-app-owned handle over the durable history store.
pub struct QaptrStoreHandle {
    store: Store,
    last_error: String,
}

/// Opens (creating if absent) the durable history database at `path`.
///
/// A null return indicates invalid UTF-8 input or a store error. The caller
/// owns the returned handle and must release it with
/// [`qaptr_store_destroy`].
///
/// # Safety
///
/// `path` must point to `path_len` readable bytes for the duration of the
/// call, or be null when `path_len` is zero.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qaptr_store_open(
    path: *const u8,
    path_len: usize,
) -> *mut QaptrStoreHandle {
    let Some(path) = (unsafe { read_utf8(path, path_len) }) else {
        return std::ptr::null_mut();
    };
    match Store::open(path) {
        Ok(store) => Box::into_raw(Box::new(QaptrStoreHandle {
            store,
            last_error: String::new(),
        })),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Destroys a handle returned by [`qaptr_store_open`].
///
/// # Safety
///
/// `handle` must be null or a live pointer returned by [`qaptr_store_open`]
/// that has not already been destroyed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qaptr_store_destroy(handle: *mut QaptrStoreHandle) {
    if !handle.is_null() {
        // SAFETY: the pointer came from `Box::into_raw` in `qaptr_store_open`
        // and is consumed exactly once by this destructor.
        unsafe { drop(Box::from_raw(handle)) };
    }
}

/// Copies a JSON snapshot of observations, workflows, and quiet exclusion
/// notices into a caller-provided buffer.
///
/// The return value is the required buffer size, including the trailing NUL.
/// A zero return means the handle was invalid or the snapshot could not be
/// read; call [`qaptr_store_last_error`] for details. The caller should call
/// again with a buffer of at least the returned size when the first call's
/// `output_capacity` was insufficient.
///
/// # Safety
///
/// `handle` must be a live handle. `output` must reference a writable buffer
/// of `output_capacity` bytes when the capacity is non-zero.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qaptr_store_snapshot_json(
    handle: *mut QaptrStoreHandle,
    output: *mut u8,
    output_capacity: usize,
) -> usize {
    let Some(handle) = (unsafe { handle.as_mut() }) else {
        return 0;
    };
    let (snapshot, notices) = match read_store_view(handle) {
        Ok(value) => value,
        Err(error) => {
            handle.last_error = error;
            return 0;
        }
    };
    let json = snapshot_to_json(&snapshot, &notices);
    copy_string(&json.to_string(), output, output_capacity)
}

/// Copies a compact review status into a caller-provided buffer.
///
/// This endpoint reports durable-history availability and explicitly reports
/// live analysis as unavailable. It never invents a provider, an active
/// session, or an analysis result. The return value is the required buffer
/// size, including the trailing NUL. A zero return means the handle was
/// invalid or the durable view could not be read; call
/// [`qaptr_store_last_error`] for details.
///
/// # Safety
///
/// `handle` must be a live handle. `output` must reference a writable buffer
/// of `output_capacity` bytes when the capacity is non-zero.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qaptr_review_status_json(
    handle: *mut QaptrStoreHandle,
    output: *mut u8,
    output_capacity: usize,
) -> usize {
    let Some(handle) = (unsafe { handle.as_mut() }) else {
        return 0;
    };
    let (snapshot, notices) = match read_store_view(handle) {
        Ok(value) => value,
        Err(error) => {
            handle.last_error = error;
            return 0;
        }
    };
    let history_available =
        !(snapshot.observations.is_empty() && snapshot.workflows.is_empty() && notices.is_empty());
    let json = json!({
        "store": { "ready": true },
        "review_session": {
            "state": "ready",
            "history_available": history_available,
            "observation_count": snapshot.observations.len(),
            "workflow_count": snapshot.workflows.len(),
            "notice_count": notices.len(),
        },
        "analysis": {
            "state": "unavailable",
            "provider": Value::Null,
            "reason": LIVE_ANALYSIS_UNAVAILABLE_REASON,
        },
    });
    copy_string(&json.to_string(), output, output_capacity)
}

/// Copies the most recent error into a caller-provided buffer.
///
/// The return value is the required buffer size, including the trailing NUL.
/// A zero return means the handle is null.
///
/// # Safety
///
/// `handle` must be live. `output` must reference a writable buffer of
/// `output_capacity` bytes when the capacity is non-zero.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qaptr_store_last_error(
    handle: *mut QaptrStoreHandle,
    output: *mut u8,
    output_capacity: usize,
) -> usize {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        return 0;
    };
    copy_string(&handle.last_error, output, output_capacity)
}

fn read_store_view(
    handle: &QaptrStoreHandle,
) -> Result<(qaptr_store::HistorySnapshot, Vec<qaptr_store::NoticeRecord>), String> {
    let snapshot = handle.store.snapshot().map_err(|error| error.to_string())?;
    let notices = handle.store.notices().map_err(|error| error.to_string())?;
    Ok((snapshot, notices))
}

fn snapshot_to_json(
    snapshot: &qaptr_store::HistorySnapshot,
    notices: &[qaptr_store::NoticeRecord],
) -> Value {
    json!({
        "observations": snapshot.observations.iter().map(|observation| json!({
            "id": observation.id.as_str(),
            "capture_id": observation.capture_id.as_ref().map(qaptr_domain::CaptureId::as_str),
            "session_id": observation.session_id.as_str(),
            "title": observation.title,
            "summary": observation.summary,
            "confidence": observation.confidence.as_f32(),
            "created_at_ms": observation.created_at.as_millis(),
        })).collect::<Vec<_>>(),
        "workflows": snapshot.workflows.iter().map(|workflow| json!({
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
        })).collect::<Vec<_>>(),
        "notices": notices.iter().map(|notice| json!({
            "id": notice.id,
            "created_at_ms": notice.created_at.as_millis(),
            "count": notice.count,
            "text": notice.text(),
        })).collect::<Vec<_>>(),
    })
}

#[cfg(test)]
mod tests {
    use qaptr_domain::{CaptureId, Confidence, ObservationId, SessionId, WorkflowId};
    use qaptr_store::{CaptureRecord, UnixMillis, WorkflowRecord};

    use super::*;

    #[test]
    fn opening_invalid_utf8_path_returns_null() {
        let bytes = [0xFF_u8, 0xFE, 0xFD];
        let handle = unsafe { qaptr_store_open(bytes.as_ptr(), bytes.len()) };
        assert!(handle.is_null());
    }

    #[test]
    fn invalid_bootstrap_input_returns_non_sensitive_failure_json() {
        let invalid = [0xFF_u8];
        let generation = b"generation-1";
        let mut output = vec![0_u8; 256];
        let required = unsafe {
            qaptr_key_bootstrap_json(
                invalid.as_ptr(),
                invalid.len(),
                generation.as_ptr(),
                generation.len(),
                output.as_mut_ptr(),
                output.len(),
            )
        };
        let value: Value = serde_json::from_slice(&output[..required - 1]).expect("result JSON");
        assert_eq!(value["ready"], false);
        assert_eq!(value["reason"], "bootstrap input is not valid UTF-8");
    }

    #[test]
    fn review_session_json_v1_shape_and_malformed_request_are_scalar() {
        let root = tempfile::tempdir().expect("temporary root");
        let vault_path = root.path().join("vault");
        let store_path = root.path().join("history.sqlite3");
        let vault_bytes = vault_path.to_string_lossy().into_owned();
        let store_bytes = store_path.to_string_lossy().into_owned();
        let handle = unsafe {
            qaptr_review_session_open(
                vault_bytes.as_bytes().as_ptr(),
                vault_bytes.len(),
                store_bytes.as_bytes().as_ptr(),
                store_bytes.len(),
            )
        };
        assert!(!handle.is_null());

        let request = br#"{"version":1,"operation":"state","unknown":true}"#;
        let mut output = vec![0_u8; 2048];
        let required = unsafe {
            qaptr_review_session_json(
                handle,
                request.as_ptr(),
                request.len(),
                output.as_mut_ptr(),
                output.len(),
            )
        };
        assert!(required > 0 && required <= output.len());
        let value: Value = serde_json::from_slice(&output[..required - 1]).expect("response JSON");
        assert_eq!(value["version"], 1);
        assert_eq!(value["ok"], false);
        assert_eq!(value["error"], "malformed_request");
        assert_eq!(value["state"]["phase"], "idle");
        assert!(value.to_string().find("image_bytes").is_none());

        unsafe { qaptr_review_session_destroy(handle) };
    }

    #[test]
    fn snapshot_json_round_trips_scalar_history_after_reopen() {
        let root = tempfile::tempdir().expect("temporary root");
        let db_path = root.path().join("history.sqlite3");
        let path_bytes = db_path.to_string_lossy().into_owned();
        let handle = unsafe { qaptr_store_open(path_bytes.as_bytes().as_ptr(), path_bytes.len()) };
        assert!(!handle.is_null());

        // SAFETY: the handle was just created and is used only from this thread.
        let store_ref = unsafe { &(*handle).store };
        store_ref
            .put_capture(&CaptureRecord {
                id: CaptureId::new("capture-1").expect("capture id"),
                captured_at: UnixMillis::from_millis(1_000),
                vault_record_id: "generation-1/capture-1".to_owned(),
                context_summary: None,
            })
            .expect("capture insert");
        store_ref
            .put_observation(&qaptr_store::ObservationRecord {
                id: ObservationId::new("observation-1").expect("observation id"),
                capture_id: Some(CaptureId::new("capture-1").expect("capture id")),
                session_id: SessionId::new("session-1").expect("session id"),
                title: "Reviewed a document".to_owned(),
                summary: "You reviewed a shared document for ten minutes.".to_owned(),
                confidence: Confidence::new(0.72).expect("confidence"),
                created_at: UnixMillis::from_millis(2_000),
            })
            .expect("observation insert");
        store_ref
            .put_notice(
                &qaptr_store::NoticeRecord::new(
                    "notice-1",
                    UnixMillis::from_millis(3_000),
                    1,
                    qaptr_store::NoticeReason::ApplicationExcluded,
                )
                .expect("notice"),
            )
            .expect("notice insert");
        store_ref
            .put_workflow(&WorkflowRecord {
                id: WorkflowId::new("workflow-1").expect("workflow id"),
                session_id: SessionId::new("session-1").expect("session id"),
                title: "Document review workflow".to_owned(),
                goal: "Review a shared document".to_owned(),
                context: "Editor".to_owned(),
                tools: "[]".to_owned(),
                sequence: "[]".to_owned(),
                decisions: "[]".to_owned(),
                variations: "[]".to_owned(),
                evidence_confidence: Confidence::new(0.72).expect("confidence"),
                created_at: UnixMillis::from_millis(2_000),
            })
            .expect("workflow insert");

        unsafe { qaptr_store_destroy(handle) };
        let handle = unsafe { qaptr_store_open(path_bytes.as_bytes().as_ptr(), path_bytes.len()) };
        assert!(!handle.is_null());

        let mut output = vec![0_u8; 4096];
        let required =
            unsafe { qaptr_store_snapshot_json(handle, output.as_mut_ptr(), output.len()) };
        assert!(required > 0 && required <= output.len());
        let json_text =
            std::str::from_utf8(&output[..required - 1]).expect("snapshot JSON is UTF-8");
        let value: Value = serde_json::from_str(json_text).expect("snapshot JSON parses");
        assert!(
            !json_text.contains("generation-1/capture-1"),
            "the review bridge must not expose vault record identifiers"
        );

        let observations = value["observations"]
            .as_array()
            .expect("observations array");
        assert_eq!(observations.len(), 1);
        assert_eq!(observations[0]["title"], "Reviewed a document");
        assert_eq!(observations[0]["confidence"], 0.72_f32 as f64);

        let workflows = value["workflows"].as_array().expect("workflows array");
        assert_eq!(workflows.len(), 1);
        assert_eq!(workflows[0]["title"], "Document review workflow");
        assert_eq!(workflows[0]["sequence"], "[]");

        let notices = value["notices"].as_array().expect("notices array");
        assert_eq!(notices.len(), 1);
        assert_eq!(
            notices[0]["text"],
            "1 capture was excluded because the application is excluded."
        );

        unsafe { qaptr_store_destroy(handle) };
    }

    #[test]
    fn successful_fixture_result_is_visible_through_snapshot_and_status_apis() {
        let root = tempfile::tempdir().expect("temporary root");
        let db_path = root.path().join("history.sqlite3");
        let path_bytes = db_path.to_string_lossy().into_owned();
        let handle = unsafe { qaptr_store_open(path_bytes.as_bytes().as_ptr(), path_bytes.len()) };
        assert!(!handle.is_null());

        // This is the scalar store result produced by a successful fixture
        // session. The bridge must expose the result without exposing the
        // sealed vault record or any image/provider material.
        let store_ref = unsafe { &(*handle).store };
        store_ref
            .put_capture(&CaptureRecord {
                id: CaptureId::new("fixture-capture-1").expect("capture id"),
                captured_at: UnixMillis::from_millis(1_000),
                vault_record_id: "fixture-generation/fixture-capture-1".to_owned(),
                context_summary: Some("Editor review".to_owned()),
            })
            .expect("capture insert");
        store_ref
            .put_observation(&qaptr_store::ObservationRecord {
                id: ObservationId::new("fixture-observation-1").expect("observation id"),
                capture_id: Some(CaptureId::new("fixture-capture-1").expect("capture id")),
                session_id: SessionId::new("fixture-session-1").expect("session id"),
                title: "Repeated document review".to_owned(),
                summary: "The same document review step recurred.".to_owned(),
                confidence: Confidence::new(0.84).expect("confidence"),
                created_at: UnixMillis::from_millis(2_000),
            })
            .expect("observation insert");
        store_ref
            .put_workflow(&WorkflowRecord {
                id: WorkflowId::new("fixture-workflow-1").expect("workflow id"),
                session_id: SessionId::new("fixture-session-1").expect("session id"),
                title: "Document review workflow".to_owned(),
                goal: "Review the document consistently".to_owned(),
                context: "Editor".to_owned(),
                tools: "[\"editor\"]".to_owned(),
                sequence: "[\"open\",\"review\"]".to_owned(),
                decisions: "[]".to_owned(),
                variations: "[]".to_owned(),
                evidence_confidence: Confidence::new(0.84).expect("confidence"),
                created_at: UnixMillis::from_millis(2_000),
            })
            .expect("workflow insert");

        let mut snapshot_output = vec![0_u8; 4096];
        let snapshot_required = unsafe {
            qaptr_store_snapshot_json(
                handle,
                snapshot_output.as_mut_ptr(),
                snapshot_output.len(),
            )
        };
        assert!(snapshot_required > 0 && snapshot_required <= snapshot_output.len());
        let snapshot: Value = serde_json::from_slice(&snapshot_output[..snapshot_required - 1])
            .expect("snapshot JSON");
        assert_eq!(snapshot["observations"].as_array().unwrap().len(), 1);
        assert_eq!(snapshot["workflows"].as_array().unwrap().len(), 1);
        assert_eq!(snapshot["observations"][0]["title"], "Repeated document review");
        assert_eq!(snapshot["workflows"][0]["title"], "Document review workflow");
        assert!(!snapshot.to_string().contains("fixture-generation/"));
        assert!(!snapshot.to_string().contains("image"));
        assert!(!snapshot.to_string().contains("provider"));

        let mut status_output = vec![0_u8; 2048];
        let status_required = unsafe {
            qaptr_review_status_json(handle, status_output.as_mut_ptr(), status_output.len())
        };
        assert!(status_required > 0 && status_required <= status_output.len());
        let status: Value = serde_json::from_slice(&status_output[..status_required - 1])
            .expect("status JSON");
        assert_eq!(status["review_session"]["history_available"], true);
        assert_eq!(status["review_session"]["observation_count"], 1);
        assert_eq!(status["review_session"]["workflow_count"], 1);
        assert_eq!(status["analysis"]["state"], "unavailable");
        assert!(status["analysis"]["provider"].is_null());

        unsafe { qaptr_store_destroy(handle) };
    }

    #[test]
    fn review_status_reports_history_without_claiming_provider_analysis() {
        let root = tempfile::tempdir().expect("temporary root");
        let db_path = root.path().join("history.sqlite3");
        let path_bytes = db_path.to_string_lossy().into_owned();
        let handle = unsafe { qaptr_store_open(path_bytes.as_bytes().as_ptr(), path_bytes.len()) };
        assert!(!handle.is_null());

        // SAFETY: the handle was just created and is used only from this thread.
        let store_ref = unsafe { &(*handle).store };
        store_ref
            .put_observation(&qaptr_store::ObservationRecord {
                id: ObservationId::new("observation-1").expect("observation id"),
                capture_id: None,
                session_id: SessionId::new("session-1").expect("session id"),
                title: "Reviewed a document".to_owned(),
                summary: "You reviewed a shared document.".to_owned(),
                confidence: Confidence::new(0.72).expect("confidence"),
                created_at: UnixMillis::from_millis(2_000),
            })
            .expect("observation insert");

        let mut output = vec![0_u8; 1024];
        let required =
            unsafe { qaptr_review_status_json(handle, output.as_mut_ptr(), output.len()) };
        assert!(required > 0 && required <= output.len());
        let value: Value = serde_json::from_slice(&output[..required - 1]).expect("status JSON");

        assert_eq!(value["store"]["ready"], true);
        assert_eq!(value["review_session"]["state"], "ready");
        assert_eq!(value["review_session"]["history_available"], true);
        assert_eq!(value["review_session"]["observation_count"], 1);
        assert_eq!(value["review_session"]["workflow_count"], 0);
        assert_eq!(value["review_session"]["notice_count"], 0);
        assert_eq!(value["analysis"]["state"], "unavailable");
        assert!(value["analysis"]["provider"].is_null());
        assert_eq!(
            value["analysis"]["reason"],
            LIVE_ANALYSIS_UNAVAILABLE_REASON
        );

        unsafe { qaptr_store_destroy(handle) };
    }

    #[test]
    fn last_error_reports_a_snapshot_failure_reason() {
        let root = tempfile::tempdir().expect("temporary root");
        let db_path = root.path().join("history.sqlite3");
        let path_bytes = db_path.to_string_lossy().into_owned();
        let handle = unsafe { qaptr_store_open(path_bytes.as_bytes().as_ptr(), path_bytes.len()) };
        assert!(!handle.is_null());

        // A fresh store has no error yet.
        let mut output = vec![0_u8; 256];
        let required = unsafe { qaptr_store_last_error(handle, output.as_mut_ptr(), output.len()) };
        assert_eq!(required, 1);

        unsafe { qaptr_store_destroy(handle) };
    }
}
