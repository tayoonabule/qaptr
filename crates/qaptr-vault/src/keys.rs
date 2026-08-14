//! Generation key material and safe identifiers.

use std::{fmt, str::FromStr};

use age::{
    secrecy::{ExposeSecret, SecretString},
    x25519,
};
use qaptr_domain::ports::CredentialValue;

use crate::{Result, VaultError};

/// A validated key-generation identifier safe for a vault path and credential key.
#[derive(Clone, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct GenerationId(String);

impl GenerationId {
    /// Creates an id and rejects path separators, traversal, and empty values.
    pub fn new(value: impl Into<String>) -> Result<Self> {
        let value = value.into();
        if value.is_empty()
            || value == "."
            || value == ".."
            || value.contains('/')
            || value.contains('\\')
            || value.contains('\0')
        {
            return Err(VaultError::InvalidId {
                kind: "generation",
                value,
            });
        }
        Ok(Self(value))
    }

    /// Returns the identifier text.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for GenerationId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(formatter)
    }
}

impl FromStr for GenerationId {
    type Err = VaultError;

    fn from_str(value: &str) -> Result<Self> {
        Self::new(value)
    }
}

/// A generation's public age/X25519 encryption key.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GenerationPublicKey(String);

impl GenerationPublicKey {
    /// Returns the encoded public key.
    pub fn as_str(&self) -> &str {
        &self.0
    }

    pub(crate) fn recipient(&self) -> Result<x25519::Recipient> {
        self.0
            .parse()
            .map_err(|error: &'static str| VaultError::InvalidKey(error.to_owned()))
    }
}

impl FromStr for GenerationPublicKey {
    type Err = VaultError;

    fn from_str(value: &str) -> Result<Self> {
        let key = Self(value.to_owned());
        key.recipient()?;
        Ok(key)
    }
}

/// A generation's private age/X25519 decryption key.
pub struct GenerationPrivateKey(SecretString);

impl GenerationPrivateKey {
    /// Parses private key material held by a credentials adapter.
    pub fn from_credential(value: &CredentialValue) -> Result<Self> {
        Self::from_str(value.expose())
    }

    /// Returns a credential value for the review app's secure credentials port.
    pub fn to_credential_value(&self) -> CredentialValue {
        CredentialValue::new(self.0.expose_secret().to_owned())
    }

    pub(crate) fn identity(&self) -> Result<x25519::Identity> {
        self.0
            .expose_secret()
            .parse()
            .map_err(|error: &'static str| VaultError::InvalidKey(error.to_owned()))
    }
}

impl FromStr for GenerationPrivateKey {
    type Err = VaultError;

    fn from_str(value: &str) -> Result<Self> {
        let identity: x25519::Identity = value
            .parse()
            .map_err(|error: &'static str| VaultError::InvalidKey(error.to_owned()))?;
        Ok(Self(identity.to_string()))
    }
}

impl fmt::Debug for GenerationPrivateKey {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("GenerationPrivateKey([redacted])")
    }
}

/// A generated public/private generation keypair.
pub struct GenerationKeypair {
    generation_id: GenerationId,
    private_key: GenerationPrivateKey,
    public_key: GenerationPublicKey,
}

impl GenerationKeypair {
    /// Generates a fresh X25519 generation keypair.
    pub fn generate(generation_id: GenerationId) -> Self {
        let identity = x25519::Identity::generate();
        let private_encoded = identity.to_string();
        let public_key = identity.to_public().to_string();
        Self {
            generation_id,
            private_key: GenerationPrivateKey(SecretString::from(private_encoded)),
            public_key: GenerationPublicKey(public_key),
        }
    }

    /// Returns the generation id.
    pub fn generation_id(&self) -> &GenerationId {
        &self.generation_id
    }

    /// Returns the public half safe to give the capture helper.
    pub fn public_key(&self) -> &GenerationPublicKey {
        &self.public_key
    }

    /// Returns the private half for secure credential storage.
    pub fn private_key(&self) -> &GenerationPrivateKey {
        &self.private_key
    }
}
