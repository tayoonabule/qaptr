//! Provider adapter trait, handshake gate, and invocation-safe request types.

use std::{fmt, num::NonZeroU32};

use thiserror::Error;

use qaptr_privacy::PreparedPayload;

use crate::{
    Capability, CapabilityDescriptor, CapabilityRequirements, RawProviderResponse, SchemaError,
    normalize_response,
};

/// A stable, non-empty provider identifier.
#[derive(Clone, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct ProviderId(String);

impl ProviderId {
    /// Creates a provider identifier, rejecting an empty value.
    pub fn new(value: impl Into<String>) -> Result<Self, ProviderRequestError> {
        let value = value.into();
        if value.trim().is_empty() {
            return Err(ProviderRequestError::EmptyField {
                field: "provider id",
            });
        }
        Ok(Self(value))
    }

    /// Returns the identifier.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for ProviderId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(formatter)
    }
}

/// An absolute executable path resolved by a future discovery adapter.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct ExecutablePath(String);

impl ExecutablePath {
    /// Creates an absolute executable path.
    pub fn new(value: impl Into<String>) -> Result<Self, ProviderRequestError> {
        let value = value.into();
        if !value.starts_with('/') {
            return Err(ProviderRequestError::NotAbsolutePath { value });
        }
        Ok(Self(value))
    }

    /// Returns the absolute path.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// An adapter-owned endpoint used by non-CLI providers.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct ProviderEndpoint(String);

impl ProviderEndpoint {
    /// Creates a non-empty endpoint descriptor without making a network call.
    pub fn new(value: impl Into<String>) -> Result<Self, ProviderRequestError> {
        let value = value.into();
        if value.trim().is_empty() {
            return Err(ProviderRequestError::EmptyField {
                field: "provider endpoint",
            });
        }
        Ok(Self(value))
    }

    /// Returns the endpoint representation.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// The local or service location that an adapter proved usable.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub enum ProviderLocation {
    /// A resolved absolute local executable.
    Executable(ExecutablePath),
    /// A configured endpoint for a non-CLI provider.
    Endpoint(ProviderEndpoint),
}

/// A comparable provider version.
#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub struct ProviderVersion {
    major: u32,
    minor: u32,
    patch: u32,
}

impl ProviderVersion {
    /// Creates a provider version from its numeric components.
    pub const fn new(major: u32, minor: u32, patch: u32) -> Self {
        Self {
            major,
            minor,
            patch,
        }
    }

    /// Returns the major version.
    pub const fn major(self) -> u32 {
        self.major
    }

    /// Returns the minor version.
    pub const fn minor(self) -> u32 {
        self.minor
    }

    /// Returns the patch version.
    pub const fn patch(self) -> u32 {
        self.patch
    }
}

impl fmt::Display for ProviderVersion {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}.{}.{}", self.major, self.minor, self.patch)
    }
}

/// How a provider obtains authentication, without exposing secret material.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AuthenticationMode {
    /// The provider uses the account already authenticated in its local CLI.
    ExistingCliSession,
    /// The provider reads a user-configured credential through the credential
    /// port owned by its adapter.
    CredentialPort,
}

/// Authentication state reported by a detection probe.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AuthenticationStatus {
    /// The provider's existing authentication is usable.
    Authenticated,
    /// The provider is installed or configured but has no usable login.
    NotAuthenticated,
}

/// Static metadata and capabilities reported by every provider adapter.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProviderDescriptor {
    id: ProviderId,
    display_name: String,
    minimum_version: ProviderVersion,
    authentication: AuthenticationMode,
    capabilities: CapabilityDescriptor,
}

impl ProviderDescriptor {
    /// Creates a provider descriptor.
    pub fn new(
        id: ProviderId,
        display_name: impl Into<String>,
        minimum_version: ProviderVersion,
        authentication: AuthenticationMode,
        capabilities: CapabilityDescriptor,
    ) -> Result<Self, ProviderRequestError> {
        let display_name = display_name.into();
        if display_name.trim().is_empty() {
            return Err(ProviderRequestError::EmptyField {
                field: "provider name",
            });
        }
        Ok(Self {
            id,
            display_name,
            minimum_version,
            authentication,
            capabilities,
        })
    }

    /// Returns the stable provider identifier.
    pub fn id(&self) -> &ProviderId {
        &self.id
    }

    /// Returns the human-readable provider name.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    /// Returns the minimum version accepted by the gate.
    pub const fn minimum_version(&self) -> ProviderVersion {
        self.minimum_version
    }

    /// Returns the authentication policy without returning a token.
    pub const fn authentication(&self) -> AuthenticationMode {
        self.authentication
    }

    /// Returns the provider's proven capability descriptor.
    pub const fn capabilities(&self) -> CapabilityDescriptor {
        self.capabilities
    }
}

/// The result of detection before the shared verification checks run.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProviderDetection {
    location: Option<ProviderLocation>,
    version: Option<ProviderVersion>,
    authentication: AuthenticationStatus,
}

impl ProviderDetection {
    /// Creates a successful detection snapshot.
    pub const fn installed(
        location: ProviderLocation,
        version: ProviderVersion,
        authentication: AuthenticationStatus,
    ) -> Self {
        Self {
            location: Some(location),
            version: Some(version),
            authentication,
        }
    }

    /// Creates a detection snapshot for an absent provider.
    pub const fn not_installed() -> Self {
        Self {
            location: None,
            version: None,
            authentication: AuthenticationStatus::NotAuthenticated,
        }
    }

    /// Returns the detected location, if one was found.
    pub fn location(&self) -> Option<&ProviderLocation> {
        self.location.as_ref()
    }

    /// Returns the detected version, if one was reported.
    pub const fn version(&self) -> Option<ProviderVersion> {
        self.version
    }

    /// Returns the detected authentication state.
    pub const fn authentication(&self) -> AuthenticationStatus {
        self.authentication
    }
}

/// An opaque proof that the shared gate accepted one provider.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct VerifiedProvider {
    descriptor: ProviderDescriptor,
    location: ProviderLocation,
    version: ProviderVersion,
}

impl VerifiedProvider {
    /// Returns the descriptor that was checked by the gate.
    pub fn descriptor(&self) -> &ProviderDescriptor {
        &self.descriptor
    }

    /// Returns the resolved location proven by the gate.
    pub fn location(&self) -> &ProviderLocation {
        &self.location
    }

    /// Returns the version proven by the gate.
    pub const fn version(&self) -> ProviderVersion {
        self.version
    }
}

/// The sanitized payload kind requested from a provider.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ProviderPayloadKind {
    /// Structured sanitized text context only.
    Text,
    /// Structured sanitized text context plus one or more masked images.
    Images,
}

/// A provider request containing no credentials and no raw capture bytes.
///
/// The fields and constructor are private. A request is assembled only inside
/// [`ProviderGate::invoke`] from a [`PreparedPayload`], so an external crate
/// cannot turn arbitrary caller-supplied text into provider input.
///
/// ```compile_fail
/// use qaptr_provider::{ProviderPayloadKind, ProviderRequest};
///
/// let _ = ProviderRequest::text("RAW SECRET password=hunter2");
///
/// let _ = ProviderRequest {
///     context: "RAW SECRET password=hunter2".to_owned(),
///     payload_kind: ProviderPayloadKind::Text,
///     image_count: None,
/// };
/// ```
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProviderRequest {
    context: String,
    payload_kind: ProviderPayloadKind,
    image_count: Option<NonZeroU32>,
}

impl ProviderRequest {
    fn from_prepared(payload: &PreparedPayload) -> Self {
        let context = payload
            .context()
            .values()
            .iter()
            .map(|value| format!("{:?}: {}", value.field(), value.value()))
            .collect::<Vec<_>>()
            .join("\n");
        let context = if context.is_empty() {
            "No structured context was available.".to_owned()
        } else {
            context
        };
        let payload_kind = if payload.masked_image().is_some() {
            ProviderPayloadKind::Images
        } else {
            ProviderPayloadKind::Text
        };
        let image_count = (payload.masked_image().is_some())
            .then(|| NonZeroU32::new(1).expect("the fixed prepared-image count is non-zero"));
        Self {
            context,
            payload_kind,
            image_count,
        }
    }

    /// Returns the sanitized context.
    pub fn context(&self) -> &str {
        &self.context
    }

    /// Returns the requested payload kind.
    pub const fn payload_kind(&self) -> ProviderPayloadKind {
        self.payload_kind
    }

    /// Returns the number of prepared images, when this is an image request.
    pub const fn image_count(&self) -> Option<NonZeroU32> {
        self.image_count
    }
}

/// The invocation proof passed from [`ProviderGate`] to an adapter.
pub struct ProviderInvocation<'a> {
    verified: &'a VerifiedProvider,
    request: &'a ProviderRequest,
}

impl<'a> ProviderInvocation<'a> {
    /// Returns the verified provider proof.
    pub fn verified_provider(&self) -> &'a VerifiedProvider {
        self.verified
    }

    /// Returns the credential-free provider request.
    pub fn request(&self) -> &'a ProviderRequest {
        self.request
    }
}

/// The only trait a concrete provider adapter must implement.
///
/// An implementation may use a subprocess runtime, an HTTP client, or an
/// in-process fake. Those mechanisms are intentionally outside this crate. The
/// trait has no credential parameter, so callers cannot send a Codex API key or
/// any other login token through the provider boundary.
pub trait ProviderAdapter {
    /// Returns the provider's identity, authentication policy, minimum version,
    /// and capabilities.
    fn descriptor(&self) -> &ProviderDescriptor;

    /// Detects the provider without returning any login token to Qaptr.
    fn detect(&self) -> Result<ProviderDetection, ProviderError>;

    /// Invokes the provider after the gate has created an invocation proof.
    fn invoke(
        &self,
        invocation: ProviderInvocation<'_>,
    ) -> Result<RawProviderResponse, ProviderError>;
}

/// Shared deny-by-default handshake and normalization gate.
pub struct ProviderGate<A> {
    adapter: A,
}

impl<A> ProviderGate<A>
where
    A: ProviderAdapter,
{
    /// Wraps an adapter in the shared provider gate.
    pub const fn new(adapter: A) -> Self {
        Self { adapter }
    }

    /// Returns a reference to the wrapped adapter.
    pub const fn adapter(&self) -> &A {
        &self.adapter
    }

    /// Detects and verifies installation, version, authentication, and the
    /// baseline capabilities required for text analysis.
    pub fn detect_and_verify(&self) -> Result<VerifiedProvider, ProviderError> {
        self.detect_and_verify_with(CapabilityRequirements::text_only())
    }

    /// Detects and verifies a provider against explicit capability needs.
    pub fn detect_and_verify_with(
        &self,
        requirements: CapabilityRequirements,
    ) -> Result<VerifiedProvider, ProviderError> {
        let descriptor = self.adapter.descriptor();
        let provider = descriptor.id().clone();
        let detection = self.adapter.detect()?;
        let location = detection
            .location
            .ok_or_else(|| ProviderError::NotInstalled {
                provider: provider.clone(),
            })?;
        let version = detection
            .version
            .ok_or_else(|| ProviderError::RuntimeFailure {
                provider: provider.clone(),
                kind: RuntimeFailureKind::VersionUnavailable,
            })?;
        if detection.authentication == AuthenticationStatus::NotAuthenticated {
            return Err(ProviderError::NotAuthenticated { provider });
        }
        if version < descriptor.minimum_version() {
            return Err(ProviderError::TooOld {
                provider,
                found: version,
                minimum: descriptor.minimum_version(),
            });
        }
        if let Some(capability) = descriptor.capabilities().missing(requirements) {
            return Err(ProviderError::CapabilityMissing {
                provider,
                capability,
            });
        }
        Ok(VerifiedProvider {
            descriptor: descriptor.clone(),
            location,
            version,
        })
    }

    /// Invokes a verified provider using only a payload that passed the privacy
    /// gate, then returns normalized output.
    pub fn invoke(
        &self,
        verified: &VerifiedProvider,
        payload: &PreparedPayload,
    ) -> Result<crate::NormalizedResponse, ProviderError> {
        let request = ProviderRequest::from_prepared(payload);
        let descriptor = self.adapter.descriptor();
        if verified.descriptor.id() != descriptor.id() {
            return Err(ProviderError::RuntimeFailure {
                provider: descriptor.id().clone(),
                kind: RuntimeFailureKind::MismatchedVerification,
            });
        }
        if request.payload_kind == ProviderPayloadKind::Images
            && !verified.descriptor.capabilities().accepts_images()
        {
            return Err(ProviderError::CapabilityMissing {
                provider: descriptor.id().clone(),
                capability: Capability::Images,
            });
        }
        let invocation = ProviderInvocation {
            verified,
            request: &request,
        };
        let raw = self.adapter.invoke(invocation)?;
        normalize_response(raw).map_err(|error| ProviderError::RuntimeFailure {
            provider: descriptor.id().clone(),
            kind: RuntimeFailureKind::MalformedOutput { error },
        })
    }
}

/// Errors returned by provider configuration constructors.
#[derive(Clone, Debug, Eq, Error, PartialEq)]
pub enum ProviderRequestError {
    /// A required textual field was empty.
    #[error("{field} must not be empty")]
    EmptyField {
        /// The name of the empty field.
        field: &'static str,
    },
    /// An executable path was not absolute.
    #[error("executable path must be absolute, got {value}")]
    NotAbsolutePath {
        /// The invalid path.
        value: String,
    },
}

/// Typed reasons for a provider invocation or probe failure.
#[derive(Clone, Debug, Error, PartialEq)]
pub enum ProviderError {
    /// No compatible executable or endpoint was found.
    #[error("{provider} is not installed or configured")]
    NotInstalled {
        /// The unavailable provider.
        provider: ProviderId,
    },
    /// The existing provider login is absent or unusable.
    #[error("{provider} is not authenticated")]
    NotAuthenticated {
        /// The unauthenticated provider.
        provider: ProviderId,
    },
    /// The detected provider is below the adapter's minimum version.
    #[error("{provider} is too old: found {found}, minimum {minimum}")]
    TooOld {
        /// The outdated provider.
        provider: ProviderId,
        /// The detected version.
        found: ProviderVersion,
        /// The minimum accepted version.
        minimum: ProviderVersion,
    },
    /// A required provider capability was not proven.
    #[error("{provider} is missing capability: {capability}")]
    CapabilityMissing {
        /// The provider that lacks the capability.
        provider: ProviderId,
        /// The missing capability.
        capability: Capability,
    },
    /// A probe or invocation failed at runtime.
    #[error("{provider} runtime failure: {kind}")]
    RuntimeFailure {
        /// The provider that failed.
        provider: ProviderId,
        /// The typed runtime failure reason.
        kind: RuntimeFailureKind,
    },
}

/// Typed runtime failure reasons carried by [`ProviderError::RuntimeFailure`].
#[derive(Clone, Debug, Error, PartialEq)]
pub enum RuntimeFailureKind {
    /// Detection could not complete.
    #[error("detection failed")]
    Detection,
    /// Detection did not report a version that could be verified.
    #[error("version unavailable")]
    VersionUnavailable,
    /// The provider process or request failed during invocation.
    #[error("invocation failed")]
    Invocation,
    /// The provider could not be reached or its transport failed.
    #[error("network failure")]
    Network,
    /// The provider rejected a request because its rate limit was reached.
    #[error("rate limited")]
    RateLimited,
    /// The provider exceeded its allowed wall-clock budget.
    #[error("timed out")]
    TimedOut,
    /// The provider was cancelled.
    #[error("cancelled")]
    Cancelled,
    /// The caller paired a proof with the wrong adapter.
    #[error("verification belongs to another provider")]
    MismatchedVerification,
    /// The adapter returned output that did not satisfy the shared schema.
    #[error("malformed output: {error}")]
    MalformedOutput {
        /// The schema error explaining the malformed output.
        error: SchemaError,
    },
}
