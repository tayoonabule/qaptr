//! Real Keychain integration tests.

#![cfg(target_os = "macos")]

use std::fs;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use qaptr_domain::ports::credentials::CredentialKey;
use qaptr_macos::MacCredentials;

#[test]
#[ignore = "writes and deletes a real user Keychain item"]
fn missing_credentials_are_absent_and_secrets_are_not_written_to_test_files() {
    let adapter = MacCredentials::new();
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("the test clock must be after the Unix epoch")
        .as_nanos();
    let key = CredentialKey::new(format!("qaptr-test-{suffix}-{}", std::process::id()))
        .expect("the generated test key must be non-empty");
    let secret = format!("qaptr-secret-{suffix}");
    let temp_root = std::env::temp_dir().join(format!("qaptr-macos-test-{suffix}"));

    fs::create_dir(&temp_root).expect("the test directory must be creatable");
    let result = (|| {
        let _ = adapter.delete_value(&key);
        assert_eq!(adapter.read_value(&key)?, None);

        let value = qaptr_domain::ports::credentials::CredentialValue::new(&secret);
        adapter.write_value(&key, &value)?;
        assert_eq!(
            adapter.read_value(&key)?.as_ref().map(|item| item.expose()),
            Some(secret.as_str())
        );
        assert!(!tree_contains(&temp_root, &secret)?);

        adapter.delete_value(&key)?;
        assert_eq!(adapter.read_value(&key)?, None);
        Ok::<(), Box<dyn std::error::Error>>(())
    })();

    let _ = adapter.delete_value(&key);
    let _ = fs::remove_dir_all(&temp_root);
    result.expect("the real Keychain round trip must succeed");
}

fn tree_contains(root: &Path, needle: &str) -> std::io::Result<bool> {
    for entry in fs::read_dir(root)? {
        let path = entry?.path();
        if path.is_dir() {
            if tree_contains(&path, needle)? {
                return Ok(true);
            }
        } else if fs::read_to_string(path)?.contains(needle) {
            return Ok(true);
        }
    }
    Ok(false)
}
