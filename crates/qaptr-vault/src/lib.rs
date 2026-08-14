//! Encrypted, ephemeral capture bundles for Qaptr.
//!
//! # Invariants
//!
//! - Sealing accepts only a generation public key. The sealing path has no
//!   private key and never calls a credentials port or the Keychain.
//! - A bundle is committed atomically. A directory without a complete marker,
//!   valid manifest, and all encrypted members is rejected rather than repaired.
//! - Generation private keys are supplied only by the credentials port on the
//!   opening path. Destroying that credential makes every bundle in the
//!   generation unreadable through Qaptr.
//! - Bundle directories are marked excluded from Time Machine backup and
//!   Spotlight indexing where the host provides those attributes.
//! - This crate never puts image bytes in plaintext metadata or durable
//!   history. The only intended plaintext-image boundary is the privacy crate's
//!   opening path; callers must not use the image access method for any other
//!   purpose.
//!
//! The crate does not claim secure physical overwriting. Cryptographic erasure
//! is achieved by destroying the generation private credential and unlinking
//! bundle files.

mod bundle;
mod fs;
mod keys;

pub use bundle::{BundleInput, BundleMetadata, OpenedBundle, PrivacyImage, SampledContext};
pub use keys::{GenerationId, GenerationKeypair, GenerationPrivateKey, GenerationPublicKey};

use std::{
    fs::File,
    io,
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
};

use age::x25519;
use fs2::FileExt;
use qaptr_domain::ports::{CredentialKey, CredentialPort};
use thiserror::Error;

/// The format version written into every bundle manifest.
pub(crate) const FORMAT_VERSION: u8 = 1;
pub(crate) const IMAGE_FILE: &str = "image.age";
pub(crate) const CONTEXT_FILE: &str = "context.age";
pub(crate) const ARTIFACTS_FILE: &str = "artifacts.age";
pub(crate) const MANIFEST_FILE: &str = "manifest";
pub(crate) const COMMITTED_FILE: &str = "COMMITTED";

static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

/// Errors returned by the encrypted capture vault.
#[derive(Debug, Error)]
pub enum VaultError {
    /// A filesystem operation failed.
    #[error("{operation} at {path}: {source}")]
    Io {
        /// The operation that failed.
        operation: &'static str,
        /// The affected path.
        path: PathBuf,
        /// The underlying operating-system error.
        #[source]
        source: io::Error,
    },
    /// An age-encrypted member could not be encrypted or decrypted.
    #[error("encrypted bundle member failed: {0}")]
    Crypto(#[source] age::EncryptError),
    /// An encrypted member could not be opened or authenticated.
    #[error("encrypted bundle member could not be opened: {0}")]
    Decrypt(#[source] age::DecryptError),
    /// A generation key was malformed.
    #[error("invalid generation key: {0}")]
    InvalidKey(String),
    /// A bundle id or generation id cannot safely name a vault entry.
    #[error("invalid {kind} id: {value}")]
    InvalidId {
        /// The kind of id.
        kind: &'static str,
        /// The rejected value.
        value: String,
    },
    /// The requested bundle does not exist.
    #[error("bundle {0} does not exist")]
    BundleNotFound(String),
    /// The bundle was found but is not fully committed.
    #[error("bundle {0} is incomplete")]
    IncompleteBundle(String),
    /// The bundle manifest is malformed or inconsistent.
    #[error("bundle {0} has an invalid manifest")]
    InvalidManifest(String),
    /// The bundle already exists.
    #[error("bundle {0} already exists")]
    BundleExists(String),
    /// The generation private key was not available from credentials.
    #[error("private key for generation {0} is unavailable")]
    PrivateKeyUnavailable(String),
    /// A credentials adapter refused a read or delete operation.
    #[error("credential operation failed: {0}")]
    Credential(String),
    /// The vault lock could not be acquired.
    #[error("could not lock vault: {0}")]
    Lock(#[source] io::Error),
    /// A bundle was deleted while it was being opened.
    #[error("bundle {0} was deleted while opening")]
    DeletedDuringOpen(String),
}

/// The result type for vault operations.
pub type Result<T> = std::result::Result<T, VaultError>;

/// A filesystem-backed encrypted capture vault.
pub struct Vault {
    root: PathBuf,
}

impl Vault {
    /// Creates a vault rooted at `path`, creating its directory structure.
    pub fn new(path: impl Into<PathBuf>) -> Result<Self> {
        let root = path.into();
        fs::create_dir_all(&root)?;
        fs::create_dir_all(&root.join("bundles"))?;
        fs::create_dir_all(&root.join("generations"))?;
        fs::mark_excluded(&root)?;
        Ok(Self { root })
    }

    /// Returns the vault root for diagnostics and adapter setup.
    pub fn root(&self) -> &Path {
        &self.root
    }

    /// Returns the secure credentials key used for a generation private key.
    pub fn generation_credential_key(generation: &GenerationId) -> Result<CredentialKey> {
        generation_credential_key(generation)
    }

    /// Stores a generation's public key where the capture helper can read it.
    /// No private material is written by this method.
    pub fn register_public_key(
        &self,
        generation: &GenerationId,
        public_key: &GenerationPublicKey,
    ) -> Result<()> {
        let _lock = self.lock()?;
        let path = self.public_key_path(generation);
        fs::atomic_write(&path, public_key.as_str().as_bytes())
    }

    /// Reads a generation public key without accessing credentials.
    pub fn public_key(&self, generation: &GenerationId) -> Result<GenerationPublicKey> {
        let path = self.public_key_path(generation);
        let bytes = fs::read(&path)?;
        let value = String::from_utf8(bytes)
            .map_err(|_| VaultError::InvalidKey("public key is not UTF-8".to_owned()))?;
        value.parse()
    }

    /// Seals a capture using only the generation public key.
    pub fn seal(
        &self,
        input: &BundleInput,
        public_key: &GenerationPublicKey,
    ) -> Result<BundleMetadata> {
        let _lock = self.lock()?;
        let bundle_dir = self.bundle_path(&input.metadata.capture_id);
        if bundle_dir.exists() {
            return Err(VaultError::BundleExists(
                input.metadata.capture_id.to_string(),
            ));
        }
        let bundles_dir = self.root.join("bundles");
        let temp_name = format!(
            ".{}.tmp-{}-{}",
            input.metadata.capture_id,
            std::process::id(),
            TEMP_COUNTER.fetch_add(1, Ordering::Relaxed)
        );
        let temp_dir = bundles_dir.join(temp_name);
        fs::create_dir(&temp_dir)?;

        let result = self.seal_into(&temp_dir, input, public_key);
        if let Err(error) = result {
            let _ = fs::remove_dir_all(&temp_dir);
            return Err(error);
        }
        fs::sync_dir(&temp_dir)?;
        fs::rename(&temp_dir, &bundle_dir)?;
        fs::sync_dir(&bundles_dir)?;
        Ok(input.metadata.clone())
    }

    /// Opens a bundle using a private key obtained directly by a trusted
    /// privacy caller. Most application code should use [`Self::open`] so the
    /// key is fetched through the credentials port.
    pub fn open_with_private_key(
        &self,
        capture_id: &qaptr_domain::CaptureId,
        private_key: &GenerationPrivateKey,
    ) -> Result<OpenedBundle> {
        let _lock = self.lock()?;
        self.open_locked(capture_id, private_key)
    }

    /// Opens a bundle after reading its generation private key through the
    /// secure credentials port. The credentials port is never used by sealing.
    pub fn open<C: CredentialPort>(
        &self,
        capture_id: &qaptr_domain::CaptureId,
        credentials: &C,
    ) -> Result<OpenedBundle> {
        let _lock = self.lock()?;
        let metadata = self.read_metadata(capture_id)?;
        let key = generation_credential_key(&metadata.generation_id)?;
        let outcome = credentials
            .read(&key)
            .map_err(|error| VaultError::Credential(error.to_string()))?;
        if outcome.is_partial() {
            return Err(VaultError::Credential(
                "partial private-key credential result".to_owned(),
            ));
        }
        let value = outcome
            .into_inner()
            .ok_or_else(|| VaultError::PrivateKeyUnavailable(metadata.generation_id.to_string()))?;
        let private_key = GenerationPrivateKey::from_credential(&value)?;
        self.open_locked(capture_id, &private_key)
    }

    /// Destroys a generation's private key through the credentials port and
    /// unlinks all of that generation's bundles. This is cryptographic erasure.
    pub fn destroy_generation<C: CredentialPort>(
        &self,
        generation: &GenerationId,
        credentials: &C,
    ) -> Result<usize> {
        let _lock = self.lock()?;
        let key = generation_credential_key(generation)?;
        let outcome = credentials
            .delete(&key)
            .map_err(|error| VaultError::Credential(error.to_string()))?;
        if outcome.is_partial() {
            return Err(VaultError::Credential(
                "partial private-key deletion result".to_owned(),
            ));
        }
        let bundles = self.root.join("bundles");
        let mut removed = 0;
        for entry in fs::read_dir(&bundles)? {
            let entry = entry.map_err(|source| VaultError::Io {
                operation: "read bundle directory entry",
                path: bundles.clone(),
                source,
            })?;
            let path = entry.path();
            if !path.is_dir()
                || path
                    .file_name()
                    .and_then(|name| name.to_str())
                    .is_some_and(|name| name.starts_with('.'))
            {
                continue;
            }
            let id = match path.file_name().and_then(|name| name.to_str()) {
                Some(value) => value,
                None => continue,
            };
            let capture_id = match qaptr_domain::CaptureId::new(id) {
                Ok(value) => value,
                Err(_) => continue,
            };
            if self
                .read_metadata(&capture_id)
                .map(|metadata| metadata.generation_id == *generation)
                .unwrap_or(false)
            {
                fs::remove_dir_all(&path)?;
                removed += 1;
            }
        }
        fs::sync_dir(&bundles)?;
        Ok(removed)
    }

    /// Deletes one bundle and leaves all other generations untouched.
    pub fn delete(&self, capture_id: &qaptr_domain::CaptureId) -> Result<bool> {
        let _lock = self.lock()?;
        let path = self.bundle_path(capture_id);
        if !path.exists() {
            return Ok(false);
        }
        fs::remove_dir_all(&path)?;
        fs::sync_dir(&self.root.join("bundles"))?;
        Ok(true)
    }

    /// Reports whether backup and Spotlight exclusion attributes are present.
    pub fn exclusions_present(&self, capture_id: &qaptr_domain::CaptureId) -> Result<bool> {
        let path = self.bundle_path(capture_id);
        if !path.exists() {
            return Err(VaultError::BundleNotFound(capture_id.to_string()));
        }
        Ok(fs::has_exclusion_attributes(&path))
    }

    fn seal_into(
        &self,
        directory: &Path,
        input: &BundleInput,
        public_key: &GenerationPublicKey,
    ) -> Result<()> {
        encrypt_member(
            directory.join(IMAGE_FILE),
            &input.image,
            public_key.recipient()?,
        )?;
        encrypt_member(
            directory.join(CONTEXT_FILE),
            input.context.as_bytes(),
            public_key.recipient()?,
        )?;
        encrypt_member(
            directory.join(ARTIFACTS_FILE),
            &input.derived_artifacts,
            public_key.recipient()?,
        )?;
        fs::atomic_write(
            &directory.join(MANIFEST_FILE),
            input.metadata.manifest().as_bytes(),
        )?;
        fs::atomic_write(&directory.join(COMMITTED_FILE), b"qaptr-vault committed\n")?;
        fs::mark_excluded(directory)?;
        Ok(())
    }

    fn open_locked(
        &self,
        capture_id: &qaptr_domain::CaptureId,
        private_key: &GenerationPrivateKey,
    ) -> Result<OpenedBundle> {
        let directory = self.bundle_path(capture_id);
        let metadata = self.read_metadata(capture_id)?;
        let identity = private_key.identity()?;
        let image = decrypt_member(&directory.join(IMAGE_FILE), &identity)?;
        let context = decrypt_member(&directory.join(CONTEXT_FILE), &identity)?;
        let derived_artifacts = decrypt_member(&directory.join(ARTIFACTS_FILE), &identity)?;
        Ok(OpenedBundle::new(
            metadata,
            image,
            context,
            derived_artifacts,
        ))
    }

    fn read_metadata(&self, capture_id: &qaptr_domain::CaptureId) -> Result<BundleMetadata> {
        let directory = self.bundle_path(capture_id);
        if !directory.exists() {
            return Err(VaultError::BundleNotFound(capture_id.to_string()));
        }
        let committed = directory.join(COMMITTED_FILE);
        if !committed.is_file() {
            return Err(VaultError::IncompleteBundle(capture_id.to_string()));
        }
        for member in [IMAGE_FILE, CONTEXT_FILE, ARTIFACTS_FILE, MANIFEST_FILE] {
            if !directory.join(member).is_file() {
                return Err(VaultError::IncompleteBundle(capture_id.to_string()));
            }
        }
        let manifest = fs::read(&directory.join(MANIFEST_FILE))?;
        BundleMetadata::from_manifest(&manifest, capture_id)
    }

    fn bundle_path(&self, capture_id: &qaptr_domain::CaptureId) -> PathBuf {
        self.root.join("bundles").join(capture_id.as_str())
    }

    fn public_key_path(&self, generation: &GenerationId) -> PathBuf {
        self.root
            .join("generations")
            .join(format!("{}.pub", generation))
    }

    fn lock(&self) -> Result<FileLock> {
        let path = self.root.join(".vault.lock");
        let file = File::options()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(&path)
            .map_err(|source| VaultError::Io {
                operation: "open vault lock",
                path,
                source,
            })?;
        file.lock_exclusive().map_err(VaultError::Lock)?;
        Ok(FileLock(file))
    }
}

struct FileLock(File);

impl Drop for FileLock {
    fn drop(&mut self) {
        let _ = self.0.unlock();
    }
}

fn generation_credential_key(generation: &GenerationId) -> Result<CredentialKey> {
    CredentialKey::new(format!("qaptr.vault.generation.{}", generation))
        .map_err(|error| VaultError::Credential(error.to_string()))
}

fn encrypt_member(path: PathBuf, plaintext: &[u8], recipient: x25519::Recipient) -> Result<()> {
    let encrypted = age::encrypt(&recipient, plaintext).map_err(VaultError::Crypto)?;
    let mut output = File::options()
        .create_new(true)
        .write(true)
        .open(&path)
        .map_err(|source| VaultError::Io {
            operation: "create encrypted member",
            path: path.clone(),
            source,
        })?;
    std::io::Write::write_all(&mut output, &encrypted).map_err(|source| VaultError::Io {
        operation: "write encrypted member",
        path: path.clone(),
        source,
    })?;
    output.sync_all().map_err(|source| VaultError::Io {
        operation: "sync encrypted member",
        path,
        source,
    })
}

fn decrypt_member(path: &Path, identity: &x25519::Identity) -> Result<Vec<u8>> {
    let bytes = fs::read(path)?;
    age::decrypt(identity, &bytes).map_err(VaultError::Decrypt)
}
