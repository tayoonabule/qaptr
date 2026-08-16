//! Structural proof that the model-policy configuration surface is non-secret.
//!
//! [`qaptr_policy::ModelPolicy`], [`qaptr_policy::ModelCatalog`], and
//! [`qaptr_policy::ModelId`] are the persistable configuration surface for
//! provider/model selection: a preferred/fallback model list and a validated
//! catalog snapshot. This file lives outside `model_policy.rs` so the
//! forbidden-token list below cannot match itself.

#[test]
fn model_policy_source_has_no_credential_or_secret_dependency() {
    let source = include_str!("../src/model_policy.rs");
    for forbidden in ["Credential", "api_key", "ApiKey", "SecretString"] {
        assert!(
            !source.contains(forbidden),
            "model_policy.rs must not reference {forbidden}"
        );
    }
}

#[test]
fn model_policy_module_is_not_declared_a_dependent_of_the_credential_port() {
    // qaptr-policy's retention module legitimately depends on
    // `qaptr_domain::ports::CredentialPort` to enforce retention against the
    // vault. model_policy.rs must not gain that same dependency: a
    // ModelPolicy/ModelCatalog value must remain safe to persist as ordinary
    // application configuration without ever touching a credential port.
    let source = include_str!("../src/model_policy.rs");
    assert!(!source.contains("ports::"));
    assert!(!source.contains("CredentialPort"));
}
