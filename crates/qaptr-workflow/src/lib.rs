//! Pure workflow documents and deterministic Markdown exports for Qaptr.
//!
//! # Invariants
//!
//! - This crate never performs I/O, calls a provider, reads capture material, or
//!   launches or executes a tool.
//! - A [`WorkflowDocument`] contains only observed or explicitly supplied
//!   material. Missing steps remain missing in every export.
//! - Renderers are deterministic functions of their input and return owned
//!   Markdown strings. They do not consult clocks, environment variables, or
//!   external state.
//! - Sanitized values are rendered with a generic phrase so exports do not leak
//!   the class of a redacted value.

pub mod document;
pub mod export;

pub use document::{
    Artifact, ConfidenceAssessment, DecisionAlternative, DecisionPoint, Provenance, Result,
    ToolObserved, Workflow, WorkflowBuilder, WorkflowDocument, WorkflowError, WorkflowStep,
    WorkflowVariation,
};
pub use export::{render_automation, render_handoff, render_onboarding, render_sop};
