//! Defensive parsing for OpenRouter's model catalog.

use qaptr_policy::ModelId;
use serde_json::{Map, Value};
use thiserror::Error;

use crate::client::MAX_RESPONSE_BYTES;

/// OpenRouter's public model-list endpoint.
pub const CATALOG_ENDPOINT: &str = "https://openrouter.ai/api/v1/models";

/// Maximum number of model entries examined from one catalog response.
pub const MAX_CATALOG_MODELS: usize = 512;

/// Errors returned when a catalog cannot produce a safe validated model set.
#[derive(Clone, Debug, Eq, Error, PartialEq)]
pub enum CatalogParseError {
    /// The response body exceeded the parser's defensive size bound.
    #[error("OpenRouter catalog response is too large")]
    ResponseTooLarge,
    /// The response was not valid JSON.
    #[error("OpenRouter catalog response is not valid JSON")]
    InvalidJson,
    /// The JSON did not contain the expected model-list envelope.
    #[error("OpenRouter catalog response has an invalid model-list envelope")]
    InvalidEnvelope,
    /// The response contained more entries than the parser will inspect.
    #[error("OpenRouter catalog contains too many model entries")]
    TooManyModels,
    /// No model satisfied the text and structured-output requirements.
    #[error("OpenRouter catalog contains no compatible structured-output models")]
    NoCompatibleModels,
}

/// Parses and validates the compatible model identifiers from an OpenRouter
/// model-list response.
///
/// Invalid, non-object, and capability-incomplete entries are ignored. The
/// whole response is rejected when its envelope is malformed or no compatible
/// model remains. Only identifiers, not provider metadata or response bodies,
/// leave this boundary.
pub fn parse_catalog(body: &str) -> Result<Vec<ModelId>, CatalogParseError> {
    if body.len() > MAX_RESPONSE_BYTES as usize {
        return Err(CatalogParseError::ResponseTooLarge);
    }
    let envelope: Value = serde_json::from_str(body).map_err(|_| CatalogParseError::InvalidJson)?;
    let entries = envelope
        .get("data")
        .and_then(Value::as_array)
        .ok_or(CatalogParseError::InvalidEnvelope)?;
    if entries.len() > MAX_CATALOG_MODELS {
        return Err(CatalogParseError::TooManyModels);
    }

    let mut models = Vec::new();
    for entry in entries {
        let Some(model) = entry.as_object() else {
            continue;
        };
        if !supports_required_capabilities(model) {
            continue;
        }
        let Some(id) = model.get("id").and_then(Value::as_str) else {
            continue;
        };
        let Ok(model_id) = ModelId::new(id.to_owned()) else {
            continue;
        };
        if !models.contains(&model_id) {
            models.push(model_id);
        }
    }

    if models.is_empty() {
        return Err(CatalogParseError::NoCompatibleModels);
    }
    Ok(models)
}

fn supports_required_capabilities(model: &Map<String, Value>) -> bool {
    has_text_modality(model, "input_modalities")
        && has_text_modality(model, "output_modalities")
        && model
            .get("supported_parameters")
            .and_then(Value::as_array)
            .is_some_and(|parameters| {
                parameters
                    .iter()
                    .any(|parameter| parameter.as_str() == Some("structured_outputs"))
            })
}

fn has_text_modality(model: &Map<String, Value>, field: &str) -> bool {
    let Some(architecture) = model.get("architecture").and_then(Value::as_object) else {
        return false;
    };
    architecture
        .get(field)
        .and_then(Value::as_array)
        .is_some_and(|modalities| {
            modalities
                .iter()
                .any(|modality| modality.as_str() == Some("text"))
        })
        || architecture
            .get("modality")
            .and_then(Value::as_str)
            .is_some_and(|modality| modality == "text->text")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn malformed_and_unstructured_entries_are_rejected_without_partial_models() {
        let body = r#"{
            "data": [
                null,
                {},
                {"id": "missing-architecture"},
                {"id": "text-only", "architecture": {
                    "input_modalities": ["text"], "output_modalities": ["text"]
                }, "supported_parameters": ["tools"]}
            ]
        }"#;

        assert_eq!(
            parse_catalog(body),
            Err(CatalogParseError::NoCompatibleModels)
        );
    }

    #[test]
    fn capability_qualified_models_are_accepted_in_source_order() {
        let body = r#"{
            "data": [
                {"id": "provider/first", "architecture": {
                    "input_modalities": ["text"], "output_modalities": ["text"]
                }, "supported_parameters": ["structured_outputs"]},
                {"id": "provider/image-only", "architecture": {
                    "input_modalities": ["image"], "output_modalities": ["text"]
                }, "supported_parameters": ["structured_outputs"]},
                {"id": "provider/second", "architecture": {
                    "input_modalities": ["text", "image"], "output_modalities": ["text"]
                }, "supported_parameters": ["structured_outputs", "tools"]},
                {"id": "provider/legacy", "architecture": {
                    "modality": "text->text"
                }, "supported_parameters": ["structured_outputs"]},
                {"id": "provider/first", "architecture": {
                    "input_modalities": ["text"], "output_modalities": ["text"]
                }, "supported_parameters": ["structured_outputs"]}
            ]
        }"#;

        let models = parse_catalog(body).expect("compatible entries should parse");
        assert_eq!(
            models.iter().map(ModelId::as_str).collect::<Vec<_>>(),
            ["provider/first", "provider/second", "provider/legacy"]
        );
    }

    #[test]
    fn oversized_catalog_is_rejected_before_json_processing() {
        let body = "{".repeat(MAX_RESPONSE_BYTES as usize + 1);

        assert_eq!(
            parse_catalog(&body),
            Err(CatalogParseError::ResponseTooLarge)
        );
    }
}
