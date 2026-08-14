//! Provider capability descriptors and request requirements.

/// A capability that can be required by the shared provider gate.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum Capability {
    /// The provider accepts a sanitized image payload.
    Images,
    /// The provider can run without an interactive terminal or prompt.
    NonInteractive,
    /// The adapter can enforce a bounded output size.
    BoundedOutput,
    /// The adapter can cancel an in-flight request.
    Cancellable,
    /// The provider invocation disables tool use.
    ToolsDisabled,
    /// The provider can run inside an isolated working directory.
    IsolatedWorkingDirectory,
    /// The provider returns a response that can be checked against the schema.
    StructuredOutput,
}

impl std::fmt::Display for Capability {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let name = match self {
            Self::Images => "images",
            Self::NonInteractive => "non-interactive invocation",
            Self::BoundedOutput => "bounded output",
            Self::Cancellable => "cancellation",
            Self::ToolsDisabled => "disabled tools",
            Self::IsolatedWorkingDirectory => "isolated working directory",
            Self::StructuredOutput => "structured output",
        };
        formatter.write_str(name)
    }
}

/// Capabilities reported by an adapter for one provider.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct CapabilityDescriptor {
    accepts_images: bool,
    non_interactive: bool,
    bounded_output: bool,
    cancellable: bool,
    tools_disabled: bool,
    isolated_working_directory: bool,
    structured_output: bool,
}

impl CapabilityDescriptor {
    /// Creates a descriptor from the capabilities proven by an adapter.
    pub const fn new(
        accepts_images: bool,
        non_interactive: bool,
        bounded_output: bool,
        cancellable: bool,
        tools_disabled: bool,
        isolated_working_directory: bool,
        structured_output: bool,
    ) -> Self {
        Self {
            accepts_images,
            non_interactive,
            bounded_output,
            cancellable,
            tools_disabled,
            isolated_working_directory,
            structured_output,
        }
    }

    /// Returns the descriptor for the minimum text-only provider contract.
    pub const fn text_only() -> Self {
        Self::new(false, true, true, true, true, true, true)
    }

    /// Returns the descriptor for a provider that also accepts images.
    pub const fn with_images() -> Self {
        Self::new(true, true, true, true, true, true, true)
    }

    /// Returns whether the provider accepts image payloads.
    pub const fn accepts_images(self) -> bool {
        self.accepts_images
    }

    /// Returns whether the provider supports non-interactive invocation.
    pub const fn supports_non_interactive(self) -> bool {
        self.non_interactive
    }

    /// Returns whether the provider supports bounded output.
    pub const fn supports_bounded_output(self) -> bool {
        self.bounded_output
    }

    /// Returns whether the provider supports cancellation.
    pub const fn supports_cancellation(self) -> bool {
        self.cancellable
    }

    /// Returns whether tool use is disabled for the provider invocation.
    pub const fn supports_disabled_tools(self) -> bool {
        self.tools_disabled
    }

    /// Returns whether the provider supports an isolated working directory.
    pub const fn supports_isolated_working_directory(self) -> bool {
        self.isolated_working_directory
    }

    /// Returns whether the provider returns schema-checkable structured output.
    pub const fn supports_structured_output(self) -> bool {
        self.structured_output
    }

    /// Finds the first missing capability for the supplied requirement.
    pub const fn missing(self, requirements: CapabilityRequirements) -> Option<Capability> {
        if requirements.images && !self.accepts_images {
            return Some(Capability::Images);
        }
        if requirements.non_interactive && !self.non_interactive {
            return Some(Capability::NonInteractive);
        }
        if requirements.bounded_output && !self.bounded_output {
            return Some(Capability::BoundedOutput);
        }
        if requirements.cancellable && !self.cancellable {
            return Some(Capability::Cancellable);
        }
        if requirements.tools_disabled && !self.tools_disabled {
            return Some(Capability::ToolsDisabled);
        }
        if requirements.isolated_working_directory && !self.isolated_working_directory {
            return Some(Capability::IsolatedWorkingDirectory);
        }
        if requirements.structured_output && !self.structured_output {
            return Some(Capability::StructuredOutput);
        }
        None
    }
}

/// Capabilities required for a provider handshake or one request.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CapabilityRequirements {
    images: bool,
    non_interactive: bool,
    bounded_output: bool,
    cancellable: bool,
    tools_disabled: bool,
    isolated_working_directory: bool,
    structured_output: bool,
}

impl CapabilityRequirements {
    /// Returns the required baseline for sanitized text-context analysis.
    pub const fn text_only() -> Self {
        Self {
            images: false,
            non_interactive: true,
            bounded_output: true,
            cancellable: true,
            tools_disabled: true,
            isolated_working_directory: true,
            structured_output: true,
        }
    }

    /// Returns the baseline requirements plus image acceptance.
    pub const fn with_images() -> Self {
        Self {
            images: true,
            ..Self::text_only()
        }
    }

    /// Returns whether this requirement includes image work.
    pub const fn requires_images(self) -> bool {
        self.images
    }
}

/// Alias retained for callers that describe a missing capability as a reason.
pub type MissingCapability = Capability;
