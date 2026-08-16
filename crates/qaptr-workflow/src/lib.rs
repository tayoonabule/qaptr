//! Pure workflow documents and deterministic Markdown exports for Qaptr.
//!
//! # Invariants
//!
//! - The document and Markdown renderer modules never perform I/O, call a
//!   provider, read capture material, or launch or execute a tool. The
//!   app-owned export saver writes only the selected rendered Markdown to the
//!   caller-supplied destination.
//! - The analysis module is the review-app-owned exception: it opens ephemeral
//!   vault bundles, invokes the privacy gate, and persists only scalar history.
//!   It never launches a worker, tool, automation, or provider with an
//!   unprepared payload.
//! - A [`WorkflowDocument`] contains only observed or explicitly supplied
//!   material. Missing steps remain missing in every export.
//! - Renderers are deterministic functions of their input and return owned
//!   Markdown strings. They do not consult clocks, environment variables, or
//!   external state.
//! - Sanitized values are rendered with a generic phrase so exports do not leak
//!   the class of a redacted value.

pub mod analyze;
pub mod consent;
pub mod document;
pub mod export;
pub mod observation;
pub mod session;

pub use analyze::{
    AnalysisError, AnalysisReport, AnalysisRunner, Cancellation, CaptureDecoder,
    CaptureRecordInput, DecodeError, ExclusionNotice, NeverCancelled, ProviderOutcome,
};
pub use consent::{
    ConsentDecision, ConsentPort, ConsentRequest, PROVIDER_DEFAULT_MODEL_LABEL, model_label,
};
pub use document::{
    Artifact, ConfidenceAssessment, DecisionAlternative, DecisionPoint, Provenance, Result,
    ToolObserved, Workflow, WorkflowBuilder, WorkflowDocument, WorkflowError, WorkflowStep,
    WorkflowVariation,
};
pub use export::{
    ExportError, MarkdownExportVariant, render_automation, render_handoff, render_onboarding,
    render_sop, save_markdown_export,
};
pub use session::{
    ReviewProgress, ReviewSessionCoordinator, ReviewSessionError, SessionCancellation,
};
