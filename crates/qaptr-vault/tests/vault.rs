//! Boundary tests for encrypted bundle sealing, opening, erasure, and races.

use std::{
    collections::HashMap,
    fs,
    path::Path,
    sync::{Arc, Barrier, Mutex},
    thread,
};

use qaptr_domain::{
    CaptureId,
    ports::{CredentialKey, CredentialPort, CredentialValue, PortOutcome, PortResult},
};
use qaptr_vault::{
    BundleInput, GenerationId, GenerationKeypair, GenerationPrivateKey, SampledContext, Vault,
    VaultError,
};

#[derive(Default)]
struct MemoryCredentials {
    values: Mutex<HashMap<String, CredentialValue>>,
}

impl CredentialPort for MemoryCredentials {
    fn read(&self, key: &CredentialKey) -> PortResult<Option<CredentialValue>> {
        let value = self
            .values
            .lock()
            .map_err(|_| qaptr_domain::DomainError::Denied {
                operation: "credential lock",
            })?
            .get(key.as_str())
            .cloned();
        Ok(PortOutcome::Complete(value))
    }

    fn write(&self, key: &CredentialKey, value: CredentialValue) -> PortResult<()> {
        self.values
            .lock()
            .map_err(|_| qaptr_domain::DomainError::Denied {
                operation: "credential lock",
            })?
            .insert(key.as_str().to_owned(), value);
        Ok(PortOutcome::Complete(()))
    }

    fn delete(&self, key: &CredentialKey) -> PortResult<()> {
        self.values
            .lock()
            .map_err(|_| qaptr_domain::DomainError::Denied {
                operation: "credential lock",
            })?
            .remove(key.as_str());
        Ok(PortOutcome::Complete(()))
    }
}

fn temporary_root() -> tempfile::TempDir {
    tempfile::tempdir().expect("test temp directory")
}

fn keypair() -> GenerationKeypair {
    GenerationKeypair::generate(GenerationId::new("generation-1").expect("generation id"))
}

fn input(id: &str, generation: &GenerationId) -> BundleInput {
    BundleInput::new(
        CaptureId::new(id).expect("capture id"),
        generation.clone(),
        b"downscaled image bytes".to_vec(),
        SampledContext::new(br#"{"application":"Editor"}"#.to_vec()),
        b"derived artifact".to_vec(),
    )
}

fn store_private_key(vault: &Vault, credentials: &MemoryCredentials, keypair: &GenerationKeypair) {
    let key = Vault::generation_credential_key(keypair.generation_id()).expect("credential key");
    credentials
        .write(&key, keypair.private_key().to_credential_value())
        .expect("store credential");
    vault
        .register_public_key(keypair.generation_id(), keypair.public_key())
        .expect("register public key");
}

#[test]
fn seal_open_round_trip_keeps_members_encrypted() {
    let root = temporary_root();
    let vault = Vault::new(root.path()).expect("vault");
    let credentials = MemoryCredentials::default();
    let keys = keypair();
    store_private_key(&vault, &credentials, &keys);

    let capture = CaptureId::new("capture-1").expect("capture id");
    vault
        .seal(
            &input(capture.as_str(), keys.generation_id()),
            keys.public_key(),
        )
        .expect("seal");
    let opened = vault.open(&capture, &credentials).expect("open");
    assert_eq!(opened.context().as_bytes(), br#"{"application":"Editor"}"#);
    assert_eq!(opened.derived_artifacts(), b"derived artifact");

    let bundle_path = root.path().join("bundles").join(capture.as_str());
    for member in ["image.age", "context.age", "artifacts.age"] {
        let ciphertext = fs::read(bundle_path.join(member)).expect("ciphertext");
        assert!(
            !ciphertext
                .windows(b"downscaled image bytes".len())
                .any(|window| window == b"downscaled image bytes")
        );
    }
    assert!(vault.exclusions_present(&capture).expect("exclusions"));
}

#[test]
fn public_key_alone_cannot_open_a_bundle() {
    let root = temporary_root();
    let vault = Vault::new(root.path()).expect("vault");
    let keys = keypair();
    let capture = CaptureId::new("capture-public-only").expect("capture id");
    vault
        .seal(
            &input(capture.as_str(), keys.generation_id()),
            keys.public_key(),
        )
        .expect("seal");

    let attempted_private: Result<GenerationPrivateKey, _> = keys.public_key().as_str().parse();
    assert!(matches!(attempted_private, Err(VaultError::InvalidKey(_))));
    let wrong_keys =
        GenerationKeypair::generate(GenerationId::new("generation-2").expect("generation id"));
    assert!(matches!(
        vault.open_with_private_key(&capture, wrong_keys.private_key()),
        Err(VaultError::Decrypt(_))
    ));
}

#[test]
fn destroying_generation_key_makes_all_generation_bundles_unreadable() {
    let root = temporary_root();
    let vault = Vault::new(root.path()).expect("vault");
    let credentials = MemoryCredentials::default();
    let keys = keypair();
    store_private_key(&vault, &credentials, &keys);
    let first = CaptureId::new("capture-first").expect("capture id");
    let second = CaptureId::new("capture-second").expect("capture id");
    vault
        .seal(
            &input(first.as_str(), keys.generation_id()),
            keys.public_key(),
        )
        .expect("seal first");
    vault
        .seal(
            &input(second.as_str(), keys.generation_id()),
            keys.public_key(),
        )
        .expect("seal second");

    assert_eq!(
        vault
            .destroy_generation(keys.generation_id(), &credentials)
            .expect("destroy generation"),
        2
    );
    assert!(matches!(
        vault.open(&first, &credentials),
        Err(VaultError::BundleNotFound(_))
    ));
    assert!(matches!(
        vault.open(&second, &credentials),
        Err(VaultError::BundleNotFound(_))
    ));
}

#[test]
fn partially_written_bundle_is_rejected_without_repair() {
    let root = temporary_root();
    let vault = Vault::new(root.path()).expect("vault");
    let keys = keypair();
    let capture = CaptureId::new("capture-partial").expect("capture id");
    let path = root.path().join("bundles").join(capture.as_str());
    fs::create_dir(&path).expect("partial bundle directory");
    fs::write(
        path.join("manifest"),
        format!(
            "version=1\ncapture_id={capture}\ngeneration_id={}\n",
            keys.generation_id()
        ),
    )
    .expect("partial manifest");

    assert!(matches!(
        vault.open_with_private_key(&capture, keys.private_key()),
        Err(VaultError::IncompleteBundle(_))
    ));
    assert!(Path::new(&path).is_dir());
    assert!(path.join("manifest").is_file());
}

#[test]
fn concurrent_seal_and_delete_leave_only_complete_or_absent_bundles() {
    let root = temporary_root();
    let vault = Arc::new(Vault::new(root.path()).expect("vault"));
    let keys = Arc::new(keypair());
    let barrier = Arc::new(Barrier::new(2));
    let capture = CaptureId::new("capture-race").expect("capture id");
    let seal_capture = capture.clone();
    let delete_capture = capture.clone();

    let seal_vault = Arc::clone(&vault);
    let seal_keys = Arc::clone(&keys);
    let seal_barrier = Arc::clone(&barrier);
    let seal_thread = thread::spawn(move || {
        seal_barrier.wait();
        seal_vault.seal(
            &input(seal_capture.as_str(), seal_keys.generation_id()),
            seal_keys.public_key(),
        )
    });
    let delete_vault = Arc::clone(&vault);
    let delete_barrier = Arc::clone(&barrier);
    let delete_thread = thread::spawn(move || {
        delete_barrier.wait();
        delete_vault.delete(&delete_capture)
    });

    let seal_result = seal_thread.join().expect("seal thread");
    let delete_result = delete_thread.join().expect("delete thread");
    assert!(seal_result.is_ok() || matches!(seal_result, Err(VaultError::BundleExists(_))));
    assert!(delete_result.is_ok());
    let bundle_path = root.path().join("bundles").join(capture.as_str());
    if bundle_path.exists() {
        assert!(
            vault
                .open_with_private_key(&capture, keys.private_key())
                .is_ok()
        );
    }
}
