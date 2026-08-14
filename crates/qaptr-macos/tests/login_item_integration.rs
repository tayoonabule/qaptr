//! Real `SMAppService` integration tests.

#![cfg(target_os = "macos")]

use qaptr_domain::ports::{LoginItemPort, LoginItemState, PortOutcome};
use qaptr_macos::MacLoginItem;

struct RestoreLoginItem {
    adapter: MacLoginItem,
    initial: LoginItemState,
}

impl Drop for RestoreLoginItem {
    fn drop(&mut self) {
        let _ = self
            .adapter
            .set_enabled(self.initial == LoginItemState::Enabled);
    }
}

#[test]
#[ignore = "mutates real SMAppService state; requires QAPTR_RUN_REAL_LOGIN_ITEM_TESTS=1"]
fn registration_is_idempotent_against_smappservice() {
    if std::env::var_os("QAPTR_RUN_REAL_LOGIN_ITEM_TESTS").is_none() {
        return;
    }

    let adapter = MacLoginItem::new();
    let initial = match adapter
        .status()
        .expect("SMAppService status must be readable")
    {
        PortOutcome::Complete(state) | PortOutcome::Partial(state) => state,
    };
    let _restore = RestoreLoginItem { adapter, initial };

    let first = adapter
        .set_enabled(true)
        .expect("first registration must succeed for a signed test app");
    assert_eq!(first.into_inner(), LoginItemState::Enabled);

    let second = adapter
        .set_enabled(true)
        .expect("re-registering an enabled item must be idempotent");
    assert_eq!(second.into_inner(), LoginItemState::Enabled);
}
