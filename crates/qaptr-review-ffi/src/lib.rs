//! Narrow C ABI for the native review app.
//!
//! # Invariants
//!
//! - This bridge exposes only durable-history reads: opening the store and
//!   returning a scalar JSON snapshot of observations, workflows, and quiet
//!   exclusion notices. It has no operation that reads a vault bundle, an
//!   image, a credential, or a provider response.
//! - All values crossing this boundary are already scalar (ids, text,
//!   confidence, and millisecond timestamps). No image bytes ever cross this
//!   ABI, mirroring `qaptr-ffi`'s helper-side invariant in the opposite
//!   direction.
//! - Errors are recorded on the handle and retrieved with
//!   [`qaptr_store_last_error`] rather than panicking across the FFI boundary.

#![allow(unsafe_code)]

mod support;
mod system;

use qaptr_store::Store;
use serde_json::{Value, json};

pub use system::{
    qaptr_login_item_set_enabled, qaptr_login_item_status, qaptr_permission_request,
    qaptr_permission_state,
};

use support::{copy_string, read_utf8};

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
    let snapshot = match handle.store.snapshot() {
        Ok(value) => value,
        Err(error) => {
            handle.last_error = error.to_string();
            return 0;
        }
    };
    let notices = match handle.store.notices() {
        Ok(value) => value,
        Err(error) => {
            handle.last_error = error.to_string();
            return 0;
        }
    };
    let json = snapshot_to_json(&snapshot, &notices);
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
    use qaptr_domain::{CaptureId, Confidence, ObservationId, SessionId};
    use qaptr_store::{CaptureRecord, UnixMillis};

    use super::*;

    #[test]
    fn opening_invalid_utf8_path_returns_null() {
        let bytes = [0xFF_u8, 0xFE, 0xFD];
        let handle = unsafe { qaptr_store_open(bytes.as_ptr(), bytes.len()) };
        assert!(handle.is_null());
    }

    #[test]
    fn snapshot_json_round_trips_observations_and_notices() {
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

        let mut output = vec![0_u8; 4096];
        let required =
            unsafe { qaptr_store_snapshot_json(handle, output.as_mut_ptr(), output.len()) };
        assert!(required > 0 && required <= output.len());
        let json_text =
            std::str::from_utf8(&output[..required - 1]).expect("snapshot JSON is UTF-8");
        let value: Value = serde_json::from_str(json_text).expect("snapshot JSON parses");

        let observations = value["observations"]
            .as_array()
            .expect("observations array");
        assert_eq!(observations.len(), 1);
        assert_eq!(observations[0]["title"], "Reviewed a document");
        assert_eq!(observations[0]["confidence"], 0.72_f32 as f64);

        let notices = value["notices"].as_array().expect("notices array");
        assert_eq!(notices.len(), 1);
        assert_eq!(
            notices[0]["text"],
            "1 capture was excluded because the application is excluded."
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
