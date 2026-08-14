//! Provider-independent decoding of bounded JSON/JSONL CLI output.

use qaptr_provider::{ProviderError, ProviderId, RawObservation, RawProviderResponse, RawWorkflow};
use serde_json::Value;

use super::malformed_output;

/// Decodes either a direct response object or a response nested in a CLI event.
///
/// Codex emits JSONL events while Jcode may emit one JSON result object. The
/// adapter boundary accepts both transport envelopes but produces one raw U13
/// response shape. No text fallback is accepted because partial natural-language
/// output would bypass schema validation.
pub(crate) fn parse_response(
    provider: &ProviderId,
    bytes: &[u8],
) -> Result<RawProviderResponse, ProviderError> {
    let text = std::str::from_utf8(bytes).map_err(|_| malformed_output(provider))?;
    let value = serde_json::from_str::<Value>(text)
        .ok()
        .and_then(find_response)
        .or_else(|| {
            text.lines()
                .filter_map(|line| serde_json::from_str::<Value>(line).ok())
                .find_map(find_response)
        })
        .ok_or_else(|| malformed_output(provider))?;
    raw_response(&value).ok_or_else(|| malformed_output(provider))
}

fn find_response(value: Value) -> Option<Value> {
    if is_response_object(&value) {
        return Some(value);
    }
    match value {
        Value::Array(values) => values.into_iter().rev().find_map(find_response),
        Value::Object(object) => {
            for key in [
                "result", "response", "output", "message", "item", "data", "text",
            ] {
                if let Some(value) = object.get(key)
                    && let Some(response) = find_response(value.clone())
                {
                    return Some(response);
                }
            }
            None
        }
        Value::String(text) => serde_json::from_str::<Value>(&text)
            .ok()
            .and_then(find_response),
        Value::Null | Value::Bool(_) | Value::Number(_) => None,
    }
}

fn is_response_object(value: &Value) -> bool {
    value
        .as_object()
        .is_some_and(|object| object.get("observations").is_some())
}

fn raw_response(value: &Value) -> Option<RawProviderResponse> {
    let object = value.as_object()?;
    let observations = object
        .get("observations")?
        .as_array()?
        .iter()
        .map(raw_observation)
        .collect::<Option<Vec<_>>>()?;
    let workflow = match object.get("workflow") {
        None | Some(Value::Null) => None,
        Some(value) => Some(raw_workflow(value)?),
    };
    Some(RawProviderResponse::new(observations, workflow))
}

fn raw_observation(value: &Value) -> Option<RawObservation> {
    let object = value.as_object()?;
    let title = object.get("title")?.as_str()?.to_owned();
    let summary = object.get("summary")?.as_str()?.to_owned();
    let confidence = object.get("confidence")?.as_f64()?;
    if !confidence.is_finite() || !(f64::from(f32::MIN)..=f64::from(f32::MAX)).contains(&confidence)
    {
        return None;
    }
    Some(RawObservation::new(title, summary, confidence as f32))
}

fn raw_workflow(value: &Value) -> Option<RawWorkflow> {
    let object = value.as_object()?;
    Some(RawWorkflow::new(
        object.get("title")?.as_str()?,
        object.get("goal")?.as_str()?,
    ))
}
