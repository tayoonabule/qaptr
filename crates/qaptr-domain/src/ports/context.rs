//! The sampled accessibility-context port.

use crate::CaptureId;

use super::PortResult;

/// A request for temporary visible context at one capture instant.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ContextRequest {
    capture: CaptureId,
}

impl ContextRequest {
    /// Creates a context request associated with a capture.
    pub const fn new(capture: CaptureId) -> Self {
        Self { capture }
    }

    /// Returns the associated capture identifier.
    pub const fn capture(&self) -> &CaptureId {
        &self.capture
    }
}

/// Temporary, user-visible context sampled at a scheduled instant.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct ContextSnapshot {
    application: Option<String>,
    window_title: Option<String>,
    browser_host: Option<String>,
    document_name: Option<String>,
}

impl ContextSnapshot {
    /// Creates a context snapshot from optional, already-reduced fields.
    pub fn new(
        application: Option<String>,
        window_title: Option<String>,
        browser_host: Option<String>,
        document_name: Option<String>,
    ) -> Self {
        Self {
            application,
            window_title,
            browser_host,
            document_name,
        }
    }

    /// Returns the active application name when available.
    pub fn application(&self) -> Option<&str> {
        self.application.as_deref()
    }

    /// Returns the active window title when available.
    pub fn window_title(&self) -> Option<&str> {
        self.window_title.as_deref()
    }

    /// Returns the reduced browser host when available.
    pub fn browser_host(&self) -> Option<&str> {
        self.browser_host.as_deref()
    }

    /// Returns the document name when available.
    pub fn document_name(&self) -> Option<&str> {
        self.document_name.as_deref()
    }
}

/// Samples temporary visible accessibility context.
pub trait AccessibilityContextPort {
    /// Samples context once for a capture and does not establish an observer.
    fn sample(&self, request: &ContextRequest) -> PortResult<ContextSnapshot>;
}

/// Short alias for callers that prefer the domain noun.
pub use AccessibilityContextPort as AccessibilityContext;
