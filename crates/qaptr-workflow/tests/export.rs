//! Acceptance and golden tests for U19 exports.

use qaptr_domain::{CaptureId, Confidence, ObservationId, SessionId, WorkflowId};
use qaptr_provider::{RawObservation, RawProviderResponse, RawWorkflow, normalize_response};
use qaptr_store::{ObservationRecord, UnixMillis};
use qaptr_workflow::{
    Artifact, ConfidenceAssessment, DecisionAlternative, DecisionPoint, Provenance, ToolObserved,
    WorkflowDocument, WorkflowStep, WorkflowVariation, render_automation, render_handoff,
    render_onboarding, render_sop,
};

fn fixture() -> WorkflowDocument {
    let session_id = SessionId::new("session-42").expect("fixture session id is valid");
    let provenance = Provenance {
        session_id: Some(session_id),
        observation_ids: vec![ObservationId::new("observation-7").expect("fixture observation id")],
        capture_ids: vec![CaptureId::new("capture-3").expect("fixture capture id")],
        note: Some("Observed during a fixed review session".to_owned()),
    };
    let high =
        ConfidenceAssessment::scored(Confidence::new(0.92).expect("fixture confidence is valid"))
            .with_basis("Repeated in the observed session");
    let moderate =
        ConfidenceAssessment::scored(Confidence::new(0.68).expect("fixture confidence is valid"))
            .with_basis("Observed once");
    let low =
        ConfidenceAssessment::scored(Confidence::new(0.32).expect("fixture confidence is valid"))
            .with_basis("Partial evidence only");

    let input = Artifact::new("Source CSV")
        .expect("fixture artifact")
        .with_description("A dated export supplied by the operations team")
        .with_confidence(high.clone())
        .with_provenance(provenance.clone());
    let optional_input = Artifact::new("Optional notes")
        .expect("fixture artifact")
        .optional()
        .with_confidence(moderate.clone());
    let output = Artifact::new("Reviewed report")
        .expect("fixture artifact")
        .with_description("A report ready for the weekly review")
        .with_confidence(high.clone());
    let tool = ToolObserved::new("Spreadsheet editor")
        .expect("fixture tool")
        .with_purpose("Inspect and annotate the source")
        .with_observed_usage("The operator filtered rows and added review notes")
        .with_confidence(high.clone())
        .with_provenance(provenance.clone());
    let first_step = WorkflowStep::new(
        "Open the source",
        "Open the dated CSV in the spreadsheet editor",
    )
    .expect("fixture step")
    .with_rationale("Establish the review period before filtering")
    .using_tool("Spreadsheet editor")
    .consuming("Source CSV")
    .producing("Open review sheet")
    .with_confidence(high.clone())
    .with_provenance(provenance.clone());
    let second_step = WorkflowStep::new(
        "Review exceptions",
        "Filter rows marked for follow-up and add notes",
    )
    .expect("fixture step")
    .with_rationale("Separate items that need an owner decision")
    .using_tool("Spreadsheet editor")
    .consuming("Open review sheet")
    .producing("Reviewed report")
    .with_confidence(low.clone());
    let decision = DecisionPoint::new("Does the row have a follow-up marker?")
        .expect("fixture decision")
        .with_answer("Add it to the reviewed report")
        .with_alternative(
            DecisionAlternative::new("No marker", "Leave the row unchanged")
                .expect("fixture alternative"),
        )
        .with_confidence(moderate.clone());
    let variation = WorkflowVariation::new(
        "Missing source date",
        "The export has no date in its filename",
        "Ask the operations owner to confirm the review period before continuing",
    )
    .expect("fixture variation")
    .with_confidence(low);

    WorkflowDocument::builder(
        WorkflowId::new("workflow-19").expect("fixture workflow id"),
        "Weekly exception review",
    )
    .goal("Prepare the reviewed report for the weekly operations meeting")
    .context("Operations reviews a dated CSV before the weekly meeting")
    .input(input)
    .input(optional_input)
    .output(output)
    .tool(tool)
    .step(first_step)
    .step(second_step)
    .decision(decision)
    .variation(variation)
    .confidence(high)
    .provenance(provenance)
    .build()
    .expect("fixture workflow is valid")
}

#[test]
fn identical_input_renders_byte_identically() {
    let first = fixture();
    let second = fixture();

    assert_eq!(render_automation(&first), render_automation(&second));
    assert_eq!(render_handoff(&first), render_handoff(&second));
    assert_eq!(render_onboarding(&first), render_onboarding(&second));
    assert_eq!(render_sop(&first), render_sop(&second));
}

#[test]
fn each_renderer_has_a_meaningfully_different_audience_shape() {
    let workflow = fixture();
    let exports = [
        render_automation(&workflow),
        render_handoff(&workflow),
        render_onboarding(&workflow),
        render_sop(&workflow),
    ];

    for (index, export) in exports.iter().enumerate() {
        for (other_index, other) in exports.iter().enumerate() {
            if index != other_index {
                assert_ne!(
                    export, other,
                    "renderer {index} matched renderer {other_index}"
                );
            }
        }
    }
    assert!(exports[0].contains("Automation boundary"));
    assert!(exports[1].contains("People and tools to align"));
    assert!(exports[2].contains("Guided walkthrough"));
    assert!(exports[3].contains("Decision table"));
}

#[test]
fn low_confidence_and_missing_material_are_not_invented() {
    let sparse = WorkflowDocument::builder(
        WorkflowId::new("workflow-empty").expect("fixture workflow id"),
        "Unfinished workflow",
    )
    .confidence(ConfidenceAssessment::unknown())
    .build()
    .expect("sparse workflow is valid");
    let rendered = [
        render_automation(&sparse),
        render_handoff(&sparse),
        render_onboarding(&sparse),
        render_sop(&sparse),
    ]
    .join("\n---\n");

    assert!(rendered.contains("No steps were captured"));
    assert!(rendered.contains("UNKNOWN (not measured)"));
    assert!(!rendered.contains("Step 1: Invented"));

    let low_step = WorkflowStep::new("Uncertain action", "A partially observed action")
        .expect("fixture step")
        .with_confidence(
            ConfidenceAssessment::scored(
                Confidence::new(0.2).expect("fixture confidence is valid"),
            )
            .with_basis("Partial evidence only"),
        );
    let low_workflow = WorkflowDocument::builder(
        WorkflowId::new("workflow-low").expect("fixture workflow id"),
        "Low confidence workflow",
    )
    .step(low_step)
    .build()
    .expect("low confidence workflow is valid");
    let low_export = render_sop(&low_workflow);
    assert!(low_export.contains("LOW (20%)"));
    assert!(low_export.contains("Partial evidence only"));
}

#[test]
fn automation_export_is_descriptive_and_redaction_safe() {
    let mut workflow = fixture();
    workflow.steps[0].action = "Use [REDACTED_API_KEY] only as observed".to_owned();
    let rendered = render_automation(&workflow);

    assert!(rendered.contains("does not launch tools"));
    assert!(!rendered.contains("[REDACTED_API_KEY]"));
    assert!(rendered.contains("[sensitive value omitted]"));
    assert!(!rendered.contains("```"));
}

#[test]
fn all_exports_match_golden_documents() {
    let workflow = fixture();
    assert_eq!(
        render_automation(&workflow),
        include_str!("snapshots/automation.md")
    );
    assert_eq!(
        render_handoff(&workflow),
        include_str!("snapshots/handoff.md")
    );
    assert_eq!(
        render_onboarding(&workflow),
        include_str!("snapshots/onboarding.md")
    );
    assert_eq!(render_sop(&workflow), include_str!("snapshots/sop.md"));
}

#[test]
fn observation_generation_is_stable_and_keeps_missing_sequence_visible() {
    let observation = ObservationRecord {
        id: ObservationId::new("observation-detail").expect("observation id"),
        capture_id: Some(CaptureId::new("capture-detail").expect("capture id")),
        session_id: SessionId::new("session-detail").expect("session id"),
        title: "Review exceptions".to_owned(),
        summary: "The operator returned to the exception list twice.".to_owned(),
        confidence: Confidence::new(0.32).expect("confidence"),
        created_at: UnixMillis::from_millis(42),
    };

    let first = WorkflowDocument::from_observation(&observation).expect("workflow document");
    let second = WorkflowDocument::from_observation(&observation).expect("workflow document");
    assert_eq!(first, second);
    assert_eq!(first.id.as_str(), "u19/observation/observation-detail");
    assert!(first.has_no_sequence());
    assert_eq!(
        first.provenance.observation_ids,
        vec![observation.id.clone()]
    );

    let record = first
        .to_record(UnixMillis::from_millis(43))
        .expect("scalar workflow record");
    assert_eq!(record.id.as_str(), first.id.as_str());
    assert!(record.sequence.contains("\"steps\":[]"));
    assert!(render_sop(&first).contains("No procedure steps were captured"));
}

#[test]
fn candidate_generation_preserves_candidate_material_without_inventing_steps() {
    let normalized = normalize_response(RawProviderResponse::new(
        vec![RawObservation::new(
            "Observed action",
            "A repeated action",
            0.88,
        )],
        Some(RawWorkflow::new(
            "Weekly review",
            "Prepare the weekly review",
        )),
    ))
    .expect("normalized candidate");
    let candidate = normalized.workflow().expect("candidate workflow");
    let session_id = SessionId::new("session-candidate").expect("session id");
    let evidence = ConfidenceAssessment::scored(Confidence::new(0.88).expect("confidence"));

    let first = WorkflowDocument::from_candidate(&session_id, candidate, 0, evidence.clone(), None)
        .expect("workflow document");
    let second = WorkflowDocument::from_candidate(&session_id, candidate, 0, evidence, None)
        .expect("workflow document");

    assert_eq!(first.id, second.id);
    assert_eq!(first.id.as_str(), "u19/session-candidate/candidate-0");
    assert_eq!(first.title, "Weekly review");
    assert_eq!(first.goal.as_deref(), Some("Prepare the weekly review"));
    assert!(first.steps.is_empty());
    assert!(render_automation(&first).contains("No steps were captured"));
}
