#![allow(missing_docs)]

use std::{
    env, fs,
    path::{Path, PathBuf},
    process::Command,
    sync::{Arc, Barrier},
    thread,
    time::{SystemTime, UNIX_EPOCH},
};

use qaptr_domain::{CaptureId, Confidence, ObservationId, SessionId, WorkflowId};
use qaptr_store::{
    CaptureRecord, ObservationRecord, Store, StoreError, UnixMillis, WorkflowRecord,
};

fn temporary_database(test_name: &str) -> (PathBuf, PathBuf) {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("the test clock must be after the Unix epoch")
        .as_nanos();
    let directory = env::temp_dir().join(format!(
        "qaptr-store-{test_name}-{}-{nonce}",
        std::process::id()
    ));
    fs::create_dir_all(&directory).expect("the temporary database directory must be creatable");
    let path = directory.join("history.sqlite3");
    (directory, path)
}

fn timestamp(value: i64) -> UnixMillis {
    UnixMillis::from_millis(value)
}

fn capture(id: &str, at: i64) -> CaptureRecord {
    CaptureRecord {
        id: CaptureId::new(id).expect("test capture ids are non-empty"),
        captured_at: timestamp(at),
        vault_record_id: format!("vault-{id}"),
        context_summary: Some("compact context".to_owned()),
    }
}

fn observation(id: &str, capture_id: Option<&str>) -> ObservationRecord {
    ObservationRecord {
        id: ObservationId::new(id).expect("test observation ids are non-empty"),
        capture_id: capture_id
            .map(|value| CaptureId::new(value).expect("test capture ids are non-empty")),
        session_id: SessionId::new("session-1").expect("test session ids are non-empty"),
        title: "Repeated export step".to_owned(),
        summary: "The same export sequence appeared twice.".to_owned(),
        confidence: Confidence::new(0.9).expect("test confidence is valid"),
        created_at: timestamp(20),
    }
}

fn workflow(id: &str) -> WorkflowRecord {
    WorkflowRecord {
        id: WorkflowId::new(id).expect("test workflow ids are non-empty"),
        session_id: SessionId::new("session-1").expect("test session ids are non-empty"),
        title: "Export a report".to_owned(),
        goal: "Create and share the report.".to_owned(),
        context: "The report is prepared at the end of the review.".to_owned(),
        tools: "Spreadsheet; browser".to_owned(),
        sequence: "Open; export; share".to_owned(),
        decisions: "Use CSV when the recipient needs raw data.".to_owned(),
        variations: "PDF is acceptable for presentation-only sharing.".to_owned(),
        evidence_confidence: Confidence::new(0.8).expect("test confidence is valid"),
        created_at: timestamp(30),
    }
}

fn remove_directory(directory: &Path) {
    fs::remove_dir_all(directory).expect("the temporary database directory must be removable");
}

#[test]
fn migration_from_empty_produces_the_allowlisted_schema() {
    let (directory, path) = temporary_database("migration");
    let store = Store::open(&path).expect("an empty database must migrate");

    assert_eq!(Store::schema_version(), 2);
    assert!(
        store
            .sqlite_version()
            .expect("SQLite version must be readable")
            .as_str()
            >= "3.51.3"
    );
    assert!(
        store
            .snapshot()
            .expect("empty schema must be readable")
            .captures
            .is_empty()
    );
    store
        .verify_schema()
        .expect("the migrated schema must be allowlisted");
    remove_directory(&directory);
}

#[test]
fn schema_guard_rejects_unallowlisted_image_material() {
    let (directory, path) = temporary_database("schema-guard");
    let store = Store::open(&path).expect("the normal schema must open");
    store
        .verify_schema()
        .expect("the normal schema must pass its guard");
    remove_directory(&directory);
}

#[test]
fn writer_accepts_a_legitimate_long_summary() {
    let (directory, path) = temporary_database("long-summary");
    let store = Store::open(&path).expect("the normal schema must open");
    let mut record = observation("long-summary", None);
    record.summary =
        "The export step remained stable while the recipient reviewed the CSV. ".repeat(100);

    store
        .put_observation(&record)
        .expect("a long human-readable summary is not image material");
    assert_eq!(
        store.snapshot().expect("snapshot must load").observations[0],
        record
    );
    remove_directory(&directory);
}

#[test]
fn writer_rejects_base64_encoded_image_material_in_text() {
    let (directory, path) = temporary_database("encoded-image");
    let store = Store::open(&path).expect("the normal schema must open");
    let mut record = observation("encoded-image", None);
    record.summary = format!("iVBORw0KGgo{}", "A".repeat(256));

    let result = store.put_observation(&record);
    assert!(matches!(
        result,
        Err(StoreError::EncodedImageMaterial { field })
            if field == "observations.summary"
    ));
    assert!(
        store
            .snapshot()
            .expect("snapshot must load")
            .observations
            .is_empty()
    );
    remove_directory(&directory);
}

#[test]
fn concurrent_readers_observe_consistent_snapshots_during_a_write() {
    let (directory, path) = temporary_database("snapshots");
    let store = Store::open(&path).expect("the database must open");
    store
        .put_capture(&capture("before", 1))
        .expect("the seed write must commit");

    let write_started = Arc::new(Barrier::new(2));
    let release_write = Arc::new(Barrier::new(2));
    let writer_store = store.clone();
    let writer_started = Arc::clone(&write_started);
    let writer_release = Arc::clone(&release_write);
    let writer = thread::spawn(move || {
        writer_store
            .transaction(|transaction| {
                transaction.put_capture(&capture("during", 2))?;
                writer_started.wait();
                writer_release.wait();
                Ok(())
            })
            .expect("the coordinated write must commit");
    });

    write_started.wait();
    let readers = (0..2)
        .map(|_| {
            let reader_store = store.clone();
            thread::spawn(move || {
                reader_store
                    .snapshot()
                    .expect("reader snapshot must succeed")
            })
        })
        .collect::<Vec<_>>();
    for reader in readers {
        let snapshot = reader.join().expect("reader thread must finish");
        assert_eq!(snapshot.captures.len(), 1);
        assert_eq!(snapshot.captures[0].id.as_str(), "before");
    }
    release_write.wait();
    writer.join().expect("writer thread must finish");

    let committed = store
        .snapshot()
        .expect("the committed snapshot must succeed");
    assert_eq!(committed.captures.len(), 2);
    remove_directory(&directory);
}

#[test]
fn crash_mid_write_leaves_a_recoverable_database() {
    let (directory, path) = temporary_database("crash");
    let store = Store::open(&path).expect("the database must open before the child crash");
    drop(store);

    let status = Command::new(env::current_exe().expect("the current test executable exists"))
        .arg("--exact")
        .arg("crash_mid_write_child")
        .arg("--nocapture")
        .env("QAPTR_STORE_CRASH_DB", &path)
        .status()
        .expect("the crash simulation child must start");
    assert!(status.success());

    let recovered = Store::open(&path).expect("the database must reopen after a crash");
    recovered
        .integrity_check()
        .expect("SQLite must recover its integrity");
    assert!(
        recovered
            .snapshot()
            .expect("the recovered snapshot must be readable")
            .captures
            .is_empty()
    );
    remove_directory(&directory);
}

#[test]
fn crash_mid_write_child() {
    let Ok(path) = env::var("QAPTR_STORE_CRASH_DB") else {
        return;
    };
    let store = Store::open(path).expect("the child database must open");
    let _ = store.transaction(|transaction| -> qaptr_store::Result<()> {
        transaction.put_capture(&capture("uncommitted", 99))?;
        std::process::exit(0);
    });
}

#[test]
fn deleting_a_capture_keeps_observations_and_workflows() {
    let (directory, path) = temporary_database("delete");
    let store = Store::open(&path).expect("the database must open");
    store
        .put_capture(&capture("to-delete", 1))
        .expect("capture must persist");
    store
        .put_observation(&observation("observation-1", Some("to-delete")))
        .expect("observation must persist");
    store
        .put_workflow(&workflow("workflow-1"))
        .expect("workflow must persist");

    assert!(
        store
            .delete_capture(&CaptureId::new("to-delete").expect("test capture id is non-empty"))
            .expect("capture deletion must succeed")
    );
    let snapshot = store.snapshot().expect("history must remain readable");
    assert!(snapshot.captures.is_empty());
    assert_eq!(snapshot.observations.len(), 1);
    assert!(snapshot.observations[0].capture_id.is_none());
    assert_eq!(snapshot.workflows.len(), 1);
    assert_eq!(snapshot.workflows[0].id.as_str(), "workflow-1");
    remove_directory(&directory);
}
