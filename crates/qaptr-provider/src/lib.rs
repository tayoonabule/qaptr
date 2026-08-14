//! Provider contracts for Qaptr's local, already-authenticated integrations.
//!
//! This crate contains only the provider boundary. It does not discover files,
//! launch processes, make HTTP requests, read credentials, or store provider
//! tokens. An adapter supplies those operations later, while [`ProviderGate`]
//! owns the shared deny-by-default handshake and invocation checks.
//!
//! # Invariants
//!
//! * A [`VerifiedProvider`] can only be created by a successful gate handshake.
//! * Provider invocations carry no credential or token argument. Authentication
//!   is an adapter-owned concern, so a CLI provider uses the account already
//!   authenticated in that CLI. In particular, Codex cannot be passed an API
//!   key through this contract.
//! * Image work is rejected before the adapter is invoked when the verified
//!   capability descriptor does not accept images.
//! * Raw adapter output is normalized and schema-validated before it leaves the
//!   provider boundary.

mod adapter;
mod capability;
mod normalize;
mod schema;

pub use adapter::{
    AuthenticationMode, AuthenticationStatus, ExecutablePath, ProviderAdapter, ProviderDescriptor,
    ProviderDetection, ProviderEndpoint, ProviderError, ProviderGate, ProviderId,
    ProviderInvocation, ProviderLocation, ProviderPayloadKind, ProviderRequest,
    ProviderRequestError, ProviderVersion, RuntimeFailureKind, VerifiedProvider,
};
pub use capability::{Capability, CapabilityDescriptor, CapabilityRequirements, MissingCapability};
pub use normalize::{
    NormalizedObservation, NormalizedResponse, NormalizedWorkflow, normalize_response,
};
pub use schema::{RawObservation, RawProviderResponse, RawWorkflow, SchemaError};
