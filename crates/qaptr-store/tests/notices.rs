//! Boundary tests for scalar-only exclusion notices.

use std::{
    env, fs,
    time::{SystemTime, UNIX_EPOCH},
};

use qaptr_store::{NoticeReason, NoticeRecord, Store, UnixMillis};

#[test]
fn notice_round_trips_without_capture_content() {
    let directory = env::temp_dir().join(format!(
        "qaptr-store-notices-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("test clock must be after the Unix epoch")
            .as_nanos()
    ));
    fs::create_dir_all(&directory).expect("notice directory");
    let store = Store::open(directory.join("history.sqlite3")).expect("store");
    let notice = NoticeRecord::new(
        "notice-1",
        UnixMillis::from_millis(10),
        2,
        NoticeReason::WindowExcluded,
    )
    .expect("notice");

    store.put_notice(&notice).expect("write notice");
    assert_eq!(store.notices().expect("read notices"), vec![notice.clone()]);
    assert_eq!(
        notice.text(),
        "2 captures were excluded because the windows are excluded."
    );
    assert!(!notice.text().contains("notice-1"));
    fs::remove_dir_all(directory).expect("remove notice directory");
}

#[test]
fn notice_constructor_rejects_whitespace_interleaved_encoded_image_id() {
    let result = NoticeRecord::new(
        "iV BO\nRw0K GgoA".to_owned() + &"A".repeat(120),
        UnixMillis::from_millis(10),
        1,
        NoticeReason::WindowExcluded,
    );
    assert!(matches!(
        result,
        Err(qaptr_store::StoreError::EncodedImageMaterial { field })
            if field == "notices.notice_id"
    ));
}

#[test]
fn notice_write_revalidates_public_record_fields() {
    let directory = env::temp_dir().join(format!(
        "qaptr-store-invalid-notice-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("test clock must be after the Unix epoch")
            .as_nanos()
    ));
    fs::create_dir_all(&directory).expect("notice directory");
    let store = Store::open(directory.join("history.sqlite3")).expect("store");
    let invalid = NoticeRecord {
        id: "iVBORw0KGgo".to_owned() + &"A".repeat(120),
        created_at: UnixMillis::from_millis(10),
        count: 1,
        reason: NoticeReason::WindowExcluded,
    };

    assert!(matches!(
        store.put_notice(&invalid),
        Err(qaptr_store::StoreError::EncodedImageMaterial { field })
            if field == "notices.notice_id"
    ));
    assert!(store.notices().expect("read notices").is_empty());
    fs::remove_dir_all(directory).expect("remove notice directory");
}
