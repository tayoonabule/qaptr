//! In-memory implementations of every U2 port.

use crate::CaptureId;
use crate::ports::capture::{CapturePort, CaptureRequest, CaptureSample};
use crate::ports::context::{AccessibilityContextPort, ContextRequest, ContextSnapshot};
use crate::ports::credentials::{CredentialKey, CredentialPort, CredentialValue};
use crate::ports::ocr::{OcrPort, OcrResult};
use crate::ports::vision::{VisionPort, VisionResult};
use crate::ports::{LoginItemPort, LoginItemState, PortResult};

use super::Response;

/// An in-memory capture adapter with a configured response.
#[derive(Clone, Debug)]
pub struct InMemoryCapture {
    response: Response<CaptureSample>,
}

impl InMemoryCapture {
    /// Creates a capture double with a complete response.
    pub fn ready(sample: CaptureSample) -> Self {
        Self {
            response: Response::Complete(sample),
        }
    }

    /// Creates a capture double that returns an incomplete sample.
    pub fn partial(sample: CaptureSample) -> Self {
        Self {
            response: Response::Partial(sample),
        }
    }

    /// Creates a capture double that simulates denial.
    pub fn denied() -> Self {
        Self {
            response: Response::Denied,
        }
    }

    /// Creates a capture double that simulates a timeout.
    pub fn timed_out() -> Self {
        Self {
            response: Response::TimedOut,
        }
    }
}

impl CapturePort for InMemoryCapture {
    fn capture(&self, _request: &CaptureRequest) -> PortResult<CaptureSample> {
        self.response.clone().into_result("capture")
    }
}

/// An in-memory OCR adapter with a configured response.
#[derive(Clone, Debug)]
pub struct InMemoryOcr {
    response: Response<OcrResult>,
}

impl InMemoryOcr {
    /// Creates an OCR double with a complete response.
    pub fn ready(result: OcrResult) -> Self {
        Self {
            response: Response::Complete(result),
        }
    }

    /// Creates an OCR double that returns an incomplete result.
    pub fn partial(result: OcrResult) -> Self {
        Self {
            response: Response::Partial(result),
        }
    }

    /// Creates an OCR double that simulates denial.
    pub fn denied() -> Self {
        Self {
            response: Response::Denied,
        }
    }

    /// Creates an OCR double that simulates a timeout.
    pub fn timed_out() -> Self {
        Self {
            response: Response::TimedOut,
        }
    }
}

impl OcrPort for InMemoryOcr {
    fn recognize(&self, _capture: &CaptureId) -> PortResult<OcrResult> {
        self.response.clone().into_result("ocr")
    }
}

/// An in-memory vision adapter with a configured response.
#[derive(Clone, Debug)]
pub struct InMemoryVision {
    response: Response<VisionResult>,
}

impl InMemoryVision {
    /// Creates a vision double with a complete response.
    pub fn ready(result: VisionResult) -> Self {
        Self {
            response: Response::Complete(result),
        }
    }

    /// Creates a vision double that returns an incomplete result.
    pub fn partial(result: VisionResult) -> Self {
        Self {
            response: Response::Partial(result),
        }
    }

    /// Creates a vision double that simulates denial.
    pub fn denied() -> Self {
        Self {
            response: Response::Denied,
        }
    }

    /// Creates a vision double that simulates a timeout.
    pub fn timed_out() -> Self {
        Self {
            response: Response::TimedOut,
        }
    }
}

impl VisionPort for InMemoryVision {
    fn detect(&self, _capture: &CaptureId) -> PortResult<VisionResult> {
        self.response.clone().into_result("vision")
    }
}

/// An in-memory accessibility-context adapter with a configured response.
#[derive(Clone, Debug)]
pub struct InMemoryAccessibilityContext {
    response: Response<ContextSnapshot>,
}

impl InMemoryAccessibilityContext {
    /// Creates a context double with a complete response.
    pub fn ready(snapshot: ContextSnapshot) -> Self {
        Self {
            response: Response::Complete(snapshot),
        }
    }

    /// Creates a context double that returns an incomplete snapshot.
    pub fn partial(snapshot: ContextSnapshot) -> Self {
        Self {
            response: Response::Partial(snapshot),
        }
    }

    /// Creates a context double that simulates denial.
    pub fn denied() -> Self {
        Self {
            response: Response::Denied,
        }
    }

    /// Creates a context double that simulates a timeout.
    pub fn timed_out() -> Self {
        Self {
            response: Response::TimedOut,
        }
    }
}

impl AccessibilityContextPort for InMemoryAccessibilityContext {
    fn sample(&self, _request: &ContextRequest) -> PortResult<ContextSnapshot> {
        self.response.clone().into_result("accessibility context")
    }
}

/// An in-memory credential adapter with independently configured operations.
#[derive(Clone, Debug)]
pub struct InMemoryCredentials {
    read_response: Response<Option<CredentialValue>>,
    write_response: Response<()>,
    delete_response: Response<()>,
}

impl InMemoryCredentials {
    /// Creates a credential double that returns `value` when read.
    pub fn ready(value: Option<CredentialValue>) -> Self {
        Self {
            read_response: Response::Complete(value),
            write_response: Response::Complete(()),
            delete_response: Response::Complete(()),
        }
    }

    /// Creates a credential double whose operations return partial outcomes.
    pub fn partial(value: Option<CredentialValue>) -> Self {
        Self {
            read_response: Response::Partial(value),
            write_response: Response::Partial(()),
            delete_response: Response::Partial(()),
        }
    }

    /// Creates a credential double whose operations are denied.
    pub fn denied() -> Self {
        Self {
            read_response: Response::Denied,
            write_response: Response::Denied,
            delete_response: Response::Denied,
        }
    }

    /// Creates a credential double whose operations time out.
    pub fn timed_out() -> Self {
        Self {
            read_response: Response::TimedOut,
            write_response: Response::TimedOut,
            delete_response: Response::TimedOut,
        }
    }
}

impl CredentialPort for InMemoryCredentials {
    fn read(&self, _key: &CredentialKey) -> PortResult<Option<CredentialValue>> {
        self.read_response.clone().into_result("credential read")
    }

    fn write(&self, _key: &CredentialKey, _value: CredentialValue) -> PortResult<()> {
        self.write_response.clone().into_result("credential write")
    }

    fn delete(&self, _key: &CredentialKey) -> PortResult<()> {
        self.delete_response
            .clone()
            .into_result("credential delete")
    }
}

/// An in-memory login-item adapter with independently configured operations.
#[derive(Clone, Debug)]
pub struct InMemoryLoginItem {
    status_response: Response<LoginItemState>,
    set_response: Response<LoginItemState>,
}

impl InMemoryLoginItem {
    /// Creates a login-item double with one state for reads and updates.
    pub fn ready(state: LoginItemState) -> Self {
        Self {
            status_response: Response::Complete(state),
            set_response: Response::Complete(state),
        }
    }

    /// Creates a login-item double that returns partial states.
    pub fn partial(state: LoginItemState) -> Self {
        Self {
            status_response: Response::Partial(state),
            set_response: Response::Partial(state),
        }
    }

    /// Creates a login-item double that simulates denial.
    pub fn denied() -> Self {
        Self {
            status_response: Response::Denied,
            set_response: Response::Denied,
        }
    }

    /// Creates a login-item double that simulates a timeout.
    pub fn timed_out() -> Self {
        Self {
            status_response: Response::TimedOut,
            set_response: Response::TimedOut,
        }
    }
}

impl LoginItemPort for InMemoryLoginItem {
    fn status(&self) -> PortResult<LoginItemState> {
        self.status_response
            .clone()
            .into_result("login-item status")
    }

    fn set_enabled(&self, _enabled: bool) -> PortResult<LoginItemState> {
        self.set_response
            .clone()
            .into_result("login-item registration")
    }
}
