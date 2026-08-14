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
