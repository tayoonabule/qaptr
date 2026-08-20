//! Review-app-owned generation-key bootstrap.
//!
//! The capture helper never links this module. It receives only the public key
//! written into the vault after the matching private key is safely present in
//! the review app's non-synchronizing Keychain namespace.

use std::{fs::File, io::ErrorKind};

use age::x25519;
use fs2::FileExt;
use qaptr_domain::ports::{CredentialKey, CredentialValue};
use qaptr_macos::MacCredentials;
use qaptr_vault::{GenerationId, GenerationKeypair, GenerationPublicKey, Vault, VaultError};

/// The outcome of reconciling one configured capture generation.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum BootstrapDisposition {
    /// Both key halves were already present and matched.
    Existing,
    /// A fresh private/public pair was created.
    Created,
    /// An existing private key was used to restore its missing public half.
    PublicKeyRestored,
}

trait SecureCredentials {
    fn contains(&self, key: &CredentialKey) -> Result<bool, String>;
    fn read(&self, key: &CredentialKey) -> Result<Option<CredentialValue>, String>;
    fn write(&self, key: &CredentialKey, value: &CredentialValue) -> Result<(), String>;
    fn delete(&self, key: &CredentialKey) -> Result<(), String>;
}

impl SecureCredentials for MacCredentials {
    fn contains(&self, key: &CredentialKey) -> Result<bool, String> {
        self.contains_value(key).map_err(|error| error.to_string())
    }

    fn read(&self, key: &CredentialKey) -> Result<Option<CredentialValue>, String> {
        self.read_value(key).map_err(|error| error.to_string())
    }

    fn write(&self, key: &CredentialKey, value: &CredentialValue) -> Result<(), String> {
        self.write_value(key, value)
            .map_err(|error| error.to_string())
    }

    fn delete(&self, key: &CredentialKey) -> Result<(), String> {
        self.delete_value(key).map_err(|error| error.to_string())
    }
}

/// Makes one generation ready for helper-side public-key sealing.
pub(crate) fn bootstrap_generation(
    vault_root: &str,
    generation: &str,
) -> Result<BootstrapDisposition, String> {
    let vault = Vault::new(vault_root).map_err(|error| error.to_string())?;
    let lock_path = vault.root().join(".bootstrap.lock");
    let lock = File::options()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(&lock_path)
        .map_err(|error| format!("could not open bootstrap lock: {error}"))?;
    lock.lock_exclusive()
        .map_err(|error| format!("could not acquire bootstrap lock: {error}"))?;
    let generation = GenerationId::new(generation).map_err(|error| error.to_string())?;
    reconcile_generation(&vault, &generation, &MacCredentials::new())
}

fn reconcile_generation<C: SecureCredentials>(
    vault: &Vault,
    generation: &GenerationId,
    credentials: &C,
) -> Result<BootstrapDisposition, String> {
    let credential_key =
        Vault::generation_credential_key(generation).map_err(|error| error.to_string())?;
    let private_key_exists = credentials.contains(&credential_key)?;
    let public_key = read_public_key(vault, generation)?;

    match (private_key_exists, public_key) {
        // Normal startup only needs capture readiness. Loading the private value
        // here can trigger a login-keychain password prompt whenever a local app
        // build receives a new signature. The vault open path still reads and
        // cryptographically validates the private key before decrypting data.
        (true, Some(_)) => Ok(BootstrapDisposition::Existing),
        (true, None) => {
            let private_value = credentials.read(&credential_key)?.ok_or_else(|| {
                "generation private key disappeared while restoring its public half".to_owned()
            })?;
            let public_key = public_key_from_private(&private_value)?;
            vault
                .register_public_key(generation, &public_key)
                .map_err(|error| error.to_string())?;
            Ok(BootstrapDisposition::PublicKeyRestored)
        }
        (false, Some(_)) => Err(
            "generation public key exists but its private key is missing from Keychain".to_owned(),
        ),
        (false, None) => {
            let keypair = GenerationKeypair::generate(generation.clone());
            let private_value = keypair.private_key().to_credential_value();
            credentials.write(&credential_key, &private_value)?;
            if let Err(error) = vault.register_public_key(generation, keypair.public_key()) {
                let rollback = credentials.delete(&credential_key);
                return match rollback {
                    Ok(()) => Err(error.to_string()),
                    Err(rollback_error) => Err(format!(
                        "{}; private-key rollback also failed: {rollback_error}",
                        error
                    )),
                };
            }
            Ok(BootstrapDisposition::Created)
        }
    }
}

fn read_public_key(
    vault: &Vault,
    generation: &GenerationId,
) -> Result<Option<GenerationPublicKey>, String> {
    match vault.public_key(generation) {
        Ok(key) => Ok(Some(key)),
        Err(VaultError::Io { source, .. }) if source.kind() == ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error.to_string()),
    }
}

fn public_key_from_private(value: &CredentialValue) -> Result<GenerationPublicKey, String> {
    let identity: x25519::Identity = value
        .expose()
        .parse()
        .map_err(|error: &'static str| format!("private generation key is invalid: {error}"))?;
    identity
        .to_public()
        .to_string()
        .parse()
        .map_err(|error: VaultError| error.to_string())
}

#[cfg(test)]
mod tests {
    use std::{
        cell::{Cell, RefCell},
        collections::HashMap,
        fs,
    };

    use super::*;

    #[derive(Default)]
    struct MemoryCredentials {
        values: RefCell<HashMap<String, CredentialValue>>,
        reads: Cell<usize>,
    }

    impl SecureCredentials for MemoryCredentials {
        fn contains(&self, key: &CredentialKey) -> Result<bool, String> {
            Ok(self.values.borrow().contains_key(key.as_str()))
        }

        fn read(&self, key: &CredentialKey) -> Result<Option<CredentialValue>, String> {
            self.reads.set(self.reads.get() + 1);
            Ok(self.values.borrow().get(key.as_str()).cloned())
        }

        fn write(&self, key: &CredentialKey, value: &CredentialValue) -> Result<(), String> {
            self.values
                .borrow_mut()
                .insert(key.as_str().to_owned(), value.clone());
            Ok(())
        }

        fn delete(&self, key: &CredentialKey) -> Result<(), String> {
            self.values.borrow_mut().remove(key.as_str());
            Ok(())
        }
    }

    fn fixture() -> (tempfile::TempDir, Vault, GenerationId, MemoryCredentials) {
        let root = tempfile::tempdir().expect("temporary vault root");
        let vault = Vault::new(root.path()).expect("vault");
        let generation = GenerationId::new("generation-1").expect("generation");
        (root, vault, generation, MemoryCredentials::default())
    }

    #[test]
    fn fresh_install_stores_private_material_only_in_credentials() {
        let (root, vault, generation, credentials) = fixture();

        let disposition = reconcile_generation(&vault, &generation, &credentials)
            .expect("fresh generation bootstrap");

        assert_eq!(disposition, BootstrapDisposition::Created);
        let key = Vault::generation_credential_key(&generation).expect("credential key");
        let private_value = credentials
            .read(&key)
            .expect("credential read")
            .expect("private key exists");
        let public_value = vault.public_key(&generation).expect("public key exists");
        assert_eq!(
            public_key_from_private(&private_value).unwrap(),
            public_value
        );

        let public_file =
            fs::read_to_string(root.path().join("generations").join("generation-1.pub"))
                .expect("public key file");
        assert!(!public_file.contains("AGE-SECRET-KEY"));
    }

    #[test]
    fn repeated_bootstrap_reuses_the_existing_generation() {
        let (_root, vault, generation, credentials) = fixture();
        assert_eq!(
            reconcile_generation(&vault, &generation, &credentials).unwrap(),
            BootstrapDisposition::Created
        );
        let key = Vault::generation_credential_key(&generation).unwrap();
        let first = credentials.read(&key).unwrap().unwrap();

        assert_eq!(
            reconcile_generation(&vault, &generation, &credentials).unwrap(),
            BootstrapDisposition::Existing
        );
        assert_eq!(credentials.read(&key).unwrap().unwrap(), first);
    }

    #[test]
    fn private_key_can_restore_a_missing_public_half() {
        let (_root, vault, generation, credentials) = fixture();
        let keypair = GenerationKeypair::generate(generation.clone());
        let key = Vault::generation_credential_key(&generation).unwrap();
        credentials
            .write(&key, &keypair.private_key().to_credential_value())
            .unwrap();

        assert_eq!(
            reconcile_generation(&vault, &generation, &credentials).unwrap(),
            BootstrapDisposition::PublicKeyRestored
        );
        assert_eq!(
            vault.public_key(&generation).unwrap(),
            *keypair.public_key()
        );
    }

    #[test]
    fn orphaned_public_key_is_not_replaced() {
        let (_root, vault, generation, credentials) = fixture();
        let keypair = GenerationKeypair::generate(generation.clone());
        vault
            .register_public_key(&generation, keypair.public_key())
            .unwrap();
        let original = vault.public_key(&generation).unwrap();

        let error = reconcile_generation(&vault, &generation, &credentials).unwrap_err();

        assert!(error.contains("private key is missing"));
        assert_eq!(vault.public_key(&generation).unwrap(), original);
    }

    #[test]
    fn normal_startup_reuses_existing_halves_without_loading_private_material() {
        let (_root, vault, generation, credentials) = fixture();
        let keypair = GenerationKeypair::generate(generation.clone());
        let key = Vault::generation_credential_key(&generation).unwrap();
        credentials
            .write(&key, &keypair.private_key().to_credential_value())
            .unwrap();
        vault
            .register_public_key(&generation, keypair.public_key())
            .unwrap();

        assert_eq!(
            reconcile_generation(&vault, &generation, &credentials).unwrap(),
            BootstrapDisposition::Existing
        );
        assert_eq!(credentials.reads.get(), 0);
    }
}
