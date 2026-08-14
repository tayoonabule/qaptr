//! Deterministic, fail-closed sanitization for sampled text context.

use std::collections::BTreeSet;

use qaptr_domain::ports::ContextSnapshot;
use thiserror::Error;

use crate::classes::{
    SensitiveClass, SensitiveFinding, classes_from_findings, detect_findings, finding_order,
};

/// The kind of sampled text being sanitized.
#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub enum ContextField {
    /// The foreground application name.
    Application,
    /// The active window title.
    WindowTitle,
    /// A browser URL or already-reduced browser host.
    Url,
    /// A local file path.
    FilePath,
    /// A document title or name.
    DocumentName,
    /// Temporary visible Accessibility text.
    AccessibilityText,
    /// A field with no reviewed classification.
    Unknown,
}

/// Errors returned when text context cannot be safely classified.
#[derive(Debug, Error, Eq, PartialEq)]
pub enum SanitizationError {
    /// The field is not one of the reviewed context classes.
    #[error("context field {field:?} has no sanitization policy")]
    UnclassifiableField {
        /// The unclassified field kind.
        field: ContextField,
    },
    /// The field contains control characters that are not safe context text.
    #[error("{field:?} contains an unsafe control character")]
    UnsafeText {
        /// The field containing the unsafe value.
        field: ContextField,
    },
    /// A URL-looking value has no usable host and is therefore removed.
    #[error("URL context has no valid host")]
    InvalidUrl,
}

/// A sanitized value and the sensitive classes replaced within it.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SanitizedValue {
    field: ContextField,
    value: String,
    classes: BTreeSet<SensitiveClass>,
}

impl SanitizedValue {
    /// Returns the source field kind.
    pub const fn field(&self) -> ContextField {
        self.field
    }

    /// Returns the provider-safe value.
    pub fn value(&self) -> &str {
        &self.value
    }

    /// Returns the classes replaced in this value.
    pub fn classes(&self) -> &BTreeSet<SensitiveClass> {
        &self.classes
    }

    /// Consumes this value and returns its provider-safe text.
    pub fn into_value(self) -> String {
        self.value
    }
}

/// The structured, provider-safe form of a context snapshot.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct SanitizedContext {
    values: Vec<SanitizedValue>,
}

impl SanitizedContext {
    /// Returns sanitized fields in the same stable order as the input snapshot.
    pub fn values(&self) -> &[SanitizedValue] {
        &self.values
    }

    /// Returns the first sanitized value for a field kind.
    pub fn get(&self, field: ContextField) -> Option<&str> {
        self.values
            .iter()
            .find(|value| value.field == field)
            .map(SanitizedValue::value)
    }

    /// Returns the union of sensitive classes replaced in this context.
    pub fn classes(&self) -> BTreeSet<SensitiveClass> {
        self.values
            .iter()
            .flat_map(|value| value.classes.iter().copied())
            .collect()
    }
}

/// Sanitizes one typed context field.
pub fn sanitize_field(
    field: ContextField,
    value: &str,
) -> Result<SanitizedValue, SanitizationError> {
    validate_text(field, value)?;
    match field {
        ContextField::Url => sanitize_url(value),
        ContextField::FilePath => sanitize_path(value),
        ContextField::Unknown => Err(SanitizationError::UnclassifiableField { field }),
        ContextField::Application
        | ContextField::WindowTitle
        | ContextField::DocumentName
        | ContextField::AccessibilityText => sanitize_text_field(field, value),
    }
}

/// Sanitizes a URL to scheme and host, dropping userinfo, port, path, query,
/// and fragment. A bare browser host is accepted because the context port may
/// already have reduced a URL before this crate receives it.
pub fn sanitize_url(value: &str) -> Result<SanitizedValue, SanitizationError> {
    validate_text(ContextField::Url, value)?;
    let trimmed = value.trim();
    let (scheme, authority) = if let Some((scheme, rest)) = trimmed.split_once("://") {
        if scheme.is_empty() || !scheme.bytes().all(|byte| byte.is_ascii_alphabetic()) {
            return Err(SanitizationError::InvalidUrl);
        }
        (Some(scheme), rest)
    } else {
        (None, trimmed)
    };
    let authority_end = authority.find(['/', '?', '#']).unwrap_or(authority.len());
    let authority = &authority[..authority_end];
    let host_with_port = authority
        .rsplit_once('@')
        .map_or(authority, |(_, host)| host);
    if host_with_port.is_empty() {
        return Err(SanitizationError::InvalidUrl);
    }
    let host = strip_port(host_with_port);
    if host.is_empty() || !valid_host(host) {
        return Err(SanitizationError::InvalidUrl);
    }
    let output = match scheme {
        Some(scheme) => format!(
            "{}://{}",
            scheme.to_ascii_lowercase(),
            host.to_ascii_lowercase()
        ),
        None => host.to_ascii_lowercase(),
    };
    let mut classes = BTreeSet::new();
    if authority.contains('@') {
        classes.insert(SensitiveClass::Credential);
    }
    if let Some((_, query)) = trimmed.split_once('?')
        && (query.contains('=') || query.to_ascii_lowercase().contains("token"))
    {
        classes.insert(SensitiveClass::ApiKey);
    }
    Ok(SanitizedValue {
        field: ContextField::Url,
        value: output,
        classes,
    })
}

/// Sanitizes a local path and replaces a home-directory username with `~`.
pub fn sanitize_path(value: &str) -> Result<SanitizedValue, SanitizationError> {
    validate_text(ContextField::FilePath, value)?;
    let generalized = generalize_home_path(value.trim());
    let text = sanitize_text_field(ContextField::FilePath, &generalized)?;
    Ok(SanitizedValue {
        field: ContextField::FilePath,
        value: text.value,
        classes: text.classes,
    })
}

/// Sanitizes ordinary application, title, document, or Accessibility text.
pub fn sanitize_text_field(
    field: ContextField,
    value: &str,
) -> Result<SanitizedValue, SanitizationError> {
    validate_text(field, value)?;
    let (url_sanitized, mut classes) = normalize_embedded_urls(value)?;
    let mut findings = detect_findings(&url_sanitized);
    findings.sort_by(finding_order);
    classes.extend(classes_from_findings(&findings));
    let output = replace_findings(&url_sanitized, &findings);
    Ok(SanitizedValue {
        field,
        value: output,
        classes,
    })
}

/// Sanitizes free-form temporary text as Accessibility text.
pub fn sanitize_text(value: &str) -> Result<SanitizedValue, SanitizationError> {
    sanitize_text_field(ContextField::AccessibilityText, value)
}

/// Sanitizes every populated field from a sampled context snapshot.
pub fn sanitize_context(snapshot: &ContextSnapshot) -> Result<SanitizedContext, SanitizationError> {
    let mut values = Vec::new();
    if let Some(application) = snapshot.application() {
        values.push(sanitize_field(ContextField::Application, application)?);
    }
    if let Some(window_title) = snapshot.window_title() {
        values.push(sanitize_field(ContextField::WindowTitle, window_title)?);
    }
    if let Some(browser_host) = snapshot.browser_host() {
        values.push(sanitize_field(ContextField::Url, browser_host)?);
    }
    if let Some(document_name) = snapshot.document_name() {
        values.push(sanitize_field(ContextField::DocumentName, document_name)?);
    }
    Ok(SanitizedContext { values })
}

fn validate_text(field: ContextField, value: &str) -> Result<(), SanitizationError> {
    if value.chars().any(char::is_control) {
        return Err(SanitizationError::UnsafeText { field });
    }
    Ok(())
}

fn replace_findings(input: &str, findings: &[SensitiveFinding]) -> String {
    let mut output = String::with_capacity(input.len());
    let mut cursor = 0;
    for finding in findings {
        if finding.start() < cursor || finding.end() > input.len() {
            continue;
        }
        output.push_str(&input[cursor..finding.start()]);
        output.push_str(finding.class().placeholder());
        cursor = finding.end();
    }
    output.push_str(&input[cursor..]);
    output
}

fn normalize_embedded_urls(
    input: &str,
) -> Result<(String, BTreeSet<SensitiveClass>), SanitizationError> {
    let mut output = String::with_capacity(input.len());
    let mut classes = BTreeSet::new();
    let mut cursor = 0;
    while cursor < input.len() {
        let character = input[cursor..]
            .chars()
            .next()
            .ok_or(SanitizationError::UnsafeText {
                field: ContextField::AccessibilityText,
            })?;
        if character.is_whitespace() {
            output.push(character);
            cursor += character.len_utf8();
            continue;
        }
        let start = cursor;
        while cursor < input.len()
            && !input[cursor..]
                .chars()
                .next()
                .is_some_and(char::is_whitespace)
        {
            let width = input[cursor..].chars().next().map_or(0, char::len_utf8);
            cursor += width;
        }
        let token = &input[start..cursor];
        if !is_url_token(token) {
            output.push_str(token);
            continue;
        }
        let end = token
            .char_indices()
            .rev()
            .find(|(_, character)| !matches!(character, '.' | ',' | ';' | ':' | '!' | '?'))
            .map_or(0, |(index, character)| index + character.len_utf8());
        let (url, trailing) = token.split_at(end);
        let sanitized = sanitize_url(url)?;
        output.push_str(sanitized.value());
        output.push_str(trailing);
        classes.extend(sanitized.classes().iter().copied());
    }
    Ok((output, classes))
}

fn is_url_token(token: &str) -> bool {
    token.starts_with("http://") || token.starts_with("https://")
}

fn generalize_home_path(path: &str) -> String {
    if let Some(rest) = path.strip_prefix("/Users/") {
        return home_rest(rest);
    }
    if let Some(rest) = path.strip_prefix("/home/") {
        return home_rest(rest);
    }
    if let Some(rest) = path.strip_prefix("~/") {
        return format!("~/{rest}");
    }
    if let Some(rest) = path.strip_prefix("file:///Users/") {
        return format!("file:///~/{}", home_rest(rest));
    }
    path.to_owned()
}

fn home_rest(rest: &str) -> String {
    rest.split_once('/')
        .map_or_else(|| "~".to_owned(), |(_, tail)| format!("~/{tail}"))
}

fn strip_port(authority: &str) -> &str {
    if authority.starts_with('[') {
        return authority
            .find(']')
            .map_or(authority, |end| &authority[..=end]);
    }
    authority
        .rsplit_once(':')
        .filter(|(_, port)| !port.is_empty() && port.bytes().all(|byte| byte.is_ascii_digit()))
        .map_or(authority, |(host, _)| host)
}

fn valid_host(host: &str) -> bool {
    if host.starts_with('[') && host.ends_with(']') {
        return host.len() > 2
            && host[1..host.len() - 1]
                .bytes()
                .all(|byte| byte.is_ascii_hexdigit() || matches!(byte, b':' | b'.'));
    }
    host.bytes()
        .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-'))
        && !host.starts_with('.')
        && !host.ends_with('.')
}
