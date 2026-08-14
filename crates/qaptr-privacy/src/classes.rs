//! Sensitive classes recognized by the context sanitizer.

use std::cmp::Ordering;
use std::collections::BTreeSet;

/// An enumerated class that the local context sanitizer replaces.
#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub enum SensitiveClass {
    /// An email address.
    EmailAddress,
    /// A telephone number.
    PhoneNumber,
    /// A username/password or other credential assignment.
    Credential,
    /// A recognizable API, access, or bearer token.
    ApiKey,
    /// A payment-card number that passes the Luhn check.
    PaymentCard,
    /// A recognizable national identifier, such as a US SSN shape.
    NationalId,
    /// A postal address with a street number and suffix.
    Address,
    /// A long token with a high-entropy shape.
    HighEntropyToken,
}

impl SensitiveClass {
    /// Returns the stable placeholder used for this class.
    pub const fn placeholder(self) -> &'static str {
        match self {
            Self::EmailAddress => "[REDACTED_EMAIL]",
            Self::PhoneNumber => "[REDACTED_PHONE]",
            Self::Credential => "[REDACTED_CREDENTIAL]",
            Self::ApiKey => "[REDACTED_API_KEY]",
            Self::PaymentCard => "[REDACTED_PAYMENT_CARD]",
            Self::NationalId => "[REDACTED_NATIONAL_ID]",
            Self::Address => "[REDACTED_ADDRESS]",
            Self::HighEntropyToken => "[REDACTED_TOKEN]",
        }
    }
}

/// A byte span detected as one sensitive class.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SensitiveFinding {
    class: SensitiveClass,
    start: usize,
    end: usize,
}

impl SensitiveFinding {
    /// Creates a finding over a UTF-8 byte span.
    pub(crate) const fn new(class: SensitiveClass, start: usize, end: usize) -> Self {
        Self { class, start, end }
    }

    /// Returns the finding's sensitive class.
    pub const fn class(self) -> SensitiveClass {
        self.class
    }

    /// Returns the inclusive start byte offset.
    pub const fn start(self) -> usize {
        self.start
    }

    /// Returns the exclusive end byte offset.
    pub const fn end(self) -> usize {
        self.end
    }
}

/// Detects the enumerated sensitive classes in text context.
///
/// Detection is intentionally conservative. It only returns findings for
/// recognizable shapes; callers must still reject malformed or unclassifiable
/// field values before building a provider payload.
pub fn detect_findings(input: &str) -> Vec<SensitiveFinding> {
    let mut findings = Vec::new();
    let tokens = tokens(input);

    for &(start, end) in &tokens {
        let token = &input[start..end];
        if looks_like_email(token) {
            findings.push(SensitiveFinding::new(
                SensitiveClass::EmailAddress,
                start,
                end,
            ));
        }
        if looks_like_national_id(token) {
            findings.push(SensitiveFinding::new(
                SensitiveClass::NationalId,
                start,
                end,
            ));
        }
        let payment_card = looks_like_payment_card(token);
        if payment_card {
            findings.push(SensitiveFinding::new(
                SensitiveClass::PaymentCard,
                start,
                end,
            ));
        }
        if !payment_card && looks_like_phone(token) {
            findings.push(SensitiveFinding::new(
                SensitiveClass::PhoneNumber,
                start,
                end,
            ));
        }
        if let Some((class, marker_start)) = assignment_finding(token) {
            findings.push(SensitiveFinding::new(class, start + marker_start, end));
        }
        if looks_like_api_key(token) {
            findings.push(SensitiveFinding::new(SensitiveClass::ApiKey, start, end));
        } else if looks_like_high_entropy_token(token) {
            findings.push(SensitiveFinding::new(
                SensitiveClass::HighEntropyToken,
                start,
                end,
            ));
        }
    }

    for window in tokens.windows(2) {
        let &(first_start, first_end) = &window[0];
        let &(second_start, second_end) = &window[1];
        let first = &input[first_start..first_end];
        let second = &input[second_start..second_end];
        if looks_like_address(first, second) {
            findings.push(SensitiveFinding::new(
                SensitiveClass::Address,
                first_start,
                second_end,
            ));
        }
    }
    for window in tokens.windows(3) {
        let &(first_start, first_end) = &window[0];
        let &(second_start, second_end) = &window[1];
        let &(third_start, third_end) = &window[2];
        let first = &input[first_start..first_end];
        let second = &input[second_start..second_end];
        let third = &input[third_start..third_end];
        if first.chars().all(|character| character.is_ascii_digit())
            && !first.is_empty()
            && !second.is_empty()
            && looks_like_street_suffix(third)
        {
            findings.push(SensitiveFinding::new(
                SensitiveClass::Address,
                first_start,
                third_end,
            ));
        }
    }

    findings.sort_by(|left, right| {
        left.start
            .cmp(&right.start)
            .then_with(|| (right.end - right.start).cmp(&(left.end - left.start)))
            .then_with(|| left.class.cmp(&right.class))
    });
    findings
}

fn tokens(input: &str) -> Vec<(usize, usize)> {
    input
        .split_whitespace()
        .filter_map(|token| {
            let start = token.as_ptr() as usize - input.as_ptr() as usize;
            let trimmed_start = token
                .char_indices()
                .find(|(_, character)| !is_token_edge(*character))
                .map_or(token.len(), |(index, _)| index);
            let trimmed_end = token
                .char_indices()
                .rev()
                .find(|(_, character)| !is_token_edge(*character))
                .map_or(0, |(index, character)| index + character.len_utf8());
            (trimmed_start < trimmed_end).then_some((start + trimmed_start, start + trimmed_end))
        })
        .collect()
}

fn is_token_edge(character: char) -> bool {
    matches!(
        character,
        '.' | ',' | ';' | ':' | '!' | '?' | ')' | ']' | '}' | '"' | '\''
    )
}

fn looks_like_email(token: &str) -> bool {
    let Some((local, domain)) = token.rsplit_once('@') else {
        return false;
    };
    !local.is_empty()
        && !domain.is_empty()
        && local
            .bytes()
            .all(|byte| byte.is_ascii_graphic() && byte != b'@')
        && domain.contains('.')
        && domain
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-'))
        && !domain.starts_with('.')
        && !domain.ends_with('.')
}

fn looks_like_national_id(token: &str) -> bool {
    let digits: String = token.chars().filter(char::is_ascii_digit).collect();
    token.len() == 11
        && token.as_bytes().get(3) == Some(&b'-')
        && token.as_bytes().get(6) == Some(&b'-')
        && digits.len() == 9
}

fn looks_like_payment_card(token: &str) -> bool {
    let digits: String = token.chars().filter(char::is_ascii_digit).collect();
    (13..=19).contains(&digits.len())
        && token
            .chars()
            .all(|character| character.is_ascii_digit() || matches!(character, ' ' | '-'))
        && luhn(&digits)
}

fn luhn(digits: &str) -> bool {
    let mut sum = 0_u32;
    let mut double = false;
    for character in digits.chars().rev() {
        let Some(mut value) = character.to_digit(10) else {
            return false;
        };
        if double {
            value *= 2;
            if value > 9 {
                value -= 9;
            }
        }
        sum += value;
        double = !double;
    }
    sum.is_multiple_of(10)
}

fn looks_like_phone(token: &str) -> bool {
    let digits = token.chars().filter(char::is_ascii_digit).count();
    let has_phone_marker =
        token.starts_with('+') || token.contains(['(', ')']) || token.contains('-');
    (7..=15).contains(&digits) && has_phone_marker
}

fn assignment_finding(token: &str) -> Option<(SensitiveClass, usize)> {
    let lower = token.to_ascii_lowercase();
    let separators = ['=', ':'];
    let marker = [
        ("password", SensitiveClass::Credential),
        ("passwd", SensitiveClass::Credential),
        ("passphrase", SensitiveClass::Credential),
        ("secret", SensitiveClass::Credential),
        ("credential", SensitiveClass::Credential),
        ("token", SensitiveClass::ApiKey),
        ("access_token", SensitiveClass::ApiKey),
        ("access-token", SensitiveClass::ApiKey),
        ("api_key", SensitiveClass::ApiKey),
        ("api-key", SensitiveClass::ApiKey),
    ];
    for (name, class) in marker {
        if let Some(index) = lower.find(name) {
            let after_name = index + name.len();
            let Some(separator_offset) = lower[after_name..]
                .char_indices()
                .find(|(_, character)| separators.contains(character))
                .map(|(offset, _)| offset)
            else {
                continue;
            };
            let value_start = after_name + separator_offset + 1;
            if value_start < token.len() && !is_placeholder(&token[value_start..]) {
                return Some((class, index));
            }
        }
    }
    None
}

fn is_placeholder(value: &str) -> bool {
    value.starts_with("[REDACTED_") && value.ends_with(']')
}

fn looks_like_api_key(token: &str) -> bool {
    [
        "sk-",
        "sk_live_",
        "sk_test_",
        "ghp_",
        "github_pat_",
        "xoxb-",
        "xoxp-",
        "AKIA",
        "Bearer_",
    ]
    .iter()
    .any(|prefix| token.starts_with(prefix) && token.len() >= prefix.len() + 8)
}

fn looks_like_high_entropy_token(token: &str) -> bool {
    if token.len() < 20 || token.contains(['/', '\\']) {
        return false;
    }
    let mut has_upper = false;
    let mut has_lower = false;
    let mut has_digit = false;
    let mut has_symbol = false;
    for character in token.chars() {
        has_upper |= character.is_ascii_uppercase();
        has_lower |= character.is_ascii_lowercase();
        has_digit |= character.is_ascii_digit();
        has_symbol |= matches!(character, '-' | '_' | '.' | '~');
    }
    [has_upper, has_lower, has_digit, has_symbol]
        .into_iter()
        .filter(|present| *present)
        .count()
        >= 3
}

fn looks_like_address(first: &str, second: &str) -> bool {
    let number = first.trim_end_matches(['.', ',']);
    number.chars().all(|character| character.is_ascii_digit())
        && !number.is_empty()
        && looks_like_street_suffix(second)
}

fn looks_like_street_suffix(value: &str) -> bool {
    matches!(
        value.to_ascii_lowercase().as_str(),
        "street"
            | "st"
            | "road"
            | "rd"
            | "avenue"
            | "ave"
            | "boulevard"
            | "blvd"
            | "drive"
            | "dr"
            | "lane"
            | "ln"
            | "court"
            | "ct"
            | "way"
            | "parkway"
            | "pkwy"
    )
}

/// Returns the set of classes represented by findings.
pub(crate) fn classes_from_findings(findings: &[SensitiveFinding]) -> BTreeSet<SensitiveClass> {
    findings.iter().map(|finding| finding.class).collect()
}

/// Orders findings by the span, then by class priority.
pub(crate) fn finding_order(left: &SensitiveFinding, right: &SensitiveFinding) -> Ordering {
    left.start
        .cmp(&right.start)
        .then_with(|| (right.end - right.start).cmp(&(left.end - left.start)))
        .then_with(|| left.class.cmp(&right.class))
}
