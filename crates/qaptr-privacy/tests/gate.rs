//! U12 fail-closed privacy gate scenarios.
//!
//! Covers refusal on every failure path, the preparation proof, opt-in
//! behaviour, and the full end-to-end preparation budget.

#![allow(clippy::expect_used, missing_docs)]

use std::{
    sync::Arc,
    time::{Duration, Instant},
};

use qaptr_domain::ports::ocr::{OcrPort, OcrResult, TextRegion};
use qaptr_domain::ports::vision::{VisionFinding, VisionKind, VisionPort, VisionResult};
use qaptr_domain::ports::{ContextSnapshot, PortOutcome};
use qaptr_domain::{CaptureId, DomainError, NormalizedRect};
use qaptr_privacy::{
    DetectionKind, ExclusionReason, FULL_PREPARATION_BUDGET, Image, ImageOrientation,
    ImageRecognizer, MASK_COLOR, MappedDetection, PreparationInput, PreparationStage, PrivacyGate,
    RecognitionResult, SensitiveClass, map_normalized_rect, measure_recall,
};

struct CompleteOcr;
struct CompleteVision;
struct PartialOcr;
struct TimeoutOcr;
struct MissingGeometryOcr;

#[derive(Debug)]
struct ImageCompleteRecognizer;

#[derive(Debug)]
struct ImagePartialRecognizer;

#[derive(Debug)]
struct ImageMissingGeometryRecognizer;
struct ImageUnboundMaskedRecognizer;

impl ImageRecognizer for ImageCompleteRecognizer {
    fn recognize_image(&self, image: &Image) -> qaptr_domain::Result<RecognitionResult> {
        if image.pixel(2, 4) == Some(MASK_COLOR) {
            return Ok(RecognitionResult::for_image(
                OcrResult::default(),
                VisionResult::default(),
                image,
            ));
        }
        let text_geometry = NormalizedRect::new(0.25, 0.25, 0.25, 0.25).expect("test geometry");
        let face_geometry = NormalizedRect::new(0.5, 0.5, 0.25, 0.25).expect("test geometry");
        Ok(RecognitionResult::for_image(
            OcrResult::new(vec![TextRegion::with_geometry(
                "fixture.email@example.test".to_owned(),
                confidence(),
                text_geometry,
            )]),
            VisionResult::new(vec![VisionFinding::with_geometry(
                VisionKind::Face,
                confidence(),
                face_geometry,
            )]),
            image,
        ))
    }
}

impl ImageRecognizer for ImagePartialRecognizer {
    fn recognize_image(&self, image: &Image) -> qaptr_domain::Result<RecognitionResult> {
        Ok(RecognitionResult::partial_for_image(
            OcrResult::default(),
            VisionResult::default(),
            image,
        ))
    }
}

impl ImageRecognizer for ImageMissingGeometryRecognizer {
    fn recognize_image(&self, image: &Image) -> qaptr_domain::Result<RecognitionResult> {
        Ok(RecognitionResult::for_image(
            OcrResult::new(vec![TextRegion::new("unmappable fixture", confidence())]),
            VisionResult::default(),
            image,
        ))
    }
}

impl ImageRecognizer for ImageUnboundMaskedRecognizer {
    fn recognize_image(&self, image: &Image) -> qaptr_domain::Result<RecognitionResult> {
        if image.pixel(2, 4) == Some(MASK_COLOR) {
            return Ok(RecognitionResult::new(
                OcrResult::default(),
                VisionResult::default(),
                &capture("unbound-rerun"),
            ));
        }
        let geometry = NormalizedRect::new(0.25, 0.25, 0.25, 0.25).expect("test geometry");
        Ok(RecognitionResult::for_image(
            OcrResult::new(vec![TextRegion::with_geometry(
                "fixture.email@example.test".to_owned(),
                confidence(),
                geometry,
            )]),
            VisionResult::default(),
            image,
        ))
    }
}

impl OcrPort for CompleteOcr {
    fn recognize(&self, _capture: &CaptureId) -> qaptr_domain::Result<PortOutcome<OcrResult>> {
        let geometry = NormalizedRect::new(0.25, 0.25, 0.25, 0.25).expect("test geometry");
        Ok(PortOutcome::Complete(OcrResult::new(vec![
            TextRegion::with_geometry(
                "fixture.email@example.test".to_owned(),
                confidence(),
                geometry,
            ),
        ])))
    }
}

impl OcrPort for PartialOcr {
    fn recognize(&self, _capture: &CaptureId) -> qaptr_domain::Result<PortOutcome<OcrResult>> {
        Ok(PortOutcome::Partial(OcrResult::default()))
    }
}

impl OcrPort for TimeoutOcr {
    fn recognize(&self, _capture: &CaptureId) -> qaptr_domain::Result<PortOutcome<OcrResult>> {
        Err(DomainError::TimedOut { operation: "ocr" })
    }
}

impl OcrPort for MissingGeometryOcr {
    fn recognize(&self, _capture: &CaptureId) -> qaptr_domain::Result<PortOutcome<OcrResult>> {
        Ok(PortOutcome::Complete(OcrResult::new(vec![
            TextRegion::new("unmappable fixture", confidence()),
        ])))
    }
}

impl OcrPort for CompleteVision {
    fn recognize(&self, _capture: &CaptureId) -> qaptr_domain::Result<PortOutcome<OcrResult>> {
        Ok(PortOutcome::Complete(OcrResult::default()))
    }
}

impl VisionPort for CompleteVision {
    fn detect(&self, _capture: &CaptureId) -> qaptr_domain::Result<PortOutcome<VisionResult>> {
        let geometry = NormalizedRect::new(0.5, 0.5, 0.25, 0.25).expect("test geometry");
        Ok(PortOutcome::Complete(VisionResult::new(vec![
            VisionFinding::with_geometry(VisionKind::Face, confidence(), geometry),
        ])))
    }
}

impl VisionPort for CompleteOcr {
    fn detect(&self, _capture: &CaptureId) -> qaptr_domain::Result<PortOutcome<VisionResult>> {
        Ok(PortOutcome::Complete(VisionResult::default()))
    }
}

impl VisionPort for PartialOcr {
    fn detect(&self, _capture: &CaptureId) -> qaptr_domain::Result<PortOutcome<VisionResult>> {
        Ok(PortOutcome::Complete(VisionResult::default()))
    }
}

impl VisionPort for TimeoutOcr {
    fn detect(&self, _capture: &CaptureId) -> qaptr_domain::Result<PortOutcome<VisionResult>> {
        Ok(PortOutcome::Complete(VisionResult::default()))
    }
}

impl VisionPort for MissingGeometryOcr {
    fn detect(&self, _capture: &CaptureId) -> qaptr_domain::Result<PortOutcome<VisionResult>> {
        Ok(PortOutcome::Complete(VisionResult::default()))
    }
}

fn confidence() -> qaptr_domain::Confidence {
    qaptr_domain::Confidence::new(0.99).expect("test confidence")
}

fn capture(name: &str) -> CaptureId {
    CaptureId::new(name).expect("test capture id")
}

fn recall() -> qaptr_privacy::RecallReport {
    measure_recall(&[], &[]).expect("empty disclosure corpus is valid")
}

fn honest_recall() -> qaptr_privacy::RecallReport {
    let ground_truth: Vec<_> = (0..6)
        .map(|index| {
            let geometry =
                NormalizedRect::new(index as f32 * 0.1, 0.1, 0.08, 0.08).expect("test geometry");
            let rect = map_normalized_rect(geometry, 100, 100, ImageOrientation::Up)
                .expect("test mapping");
            MappedDetection::new(DetectionKind::Text, rect)
        })
        .collect();
    measure_recall(&ground_truth, &ground_truth[..5]).expect("known miss is valid")
}

fn safe_context() -> ContextSnapshot {
    ContextSnapshot::new(
        Some("Safari".to_owned()),
        Some("Review fixture".to_owned()),
        Some("https://example.test".to_owned()),
        Some("plan.md".to_owned()),
    )
}

fn image_input_with(recognizer: Arc<dyn ImageRecognizer>) -> PreparationInput {
    PreparationInput::new(capture("image"), safe_context())
        .with_image(
            Image::solid(8, 8, [255, 255, 255]).expect("test image"),
            ImageOrientation::Up,
        )
        .with_image_recognizer(recognizer)
        .allow_image()
}

fn image_input() -> PreparationInput {
    image_input_with(Arc::new(ImageCompleteRecognizer))
}

#[test]
fn recognition_timeout_refuses_to_emit() {
    let result = PrivacyGate::new(recall()).prepare(
        PreparationInput::new(capture("timeout"), safe_context()),
        &TimeoutOcr,
        &CompleteVision,
    );

    assert!(matches!(
        result,
        Err(exclusion) if matches!(exclusion.reason(), ExclusionReason::Recognition(DomainError::TimedOut { operation: "ocr" }))
    ));
}

#[test]
fn partial_recognition_refuses_to_emit() {
    let result = PrivacyGate::new(recall()).prepare(
        image_input_with(Arc::new(ImagePartialRecognizer)),
        &PartialOcr,
        &PartialOcr,
    );

    assert!(matches!(
        result,
        Err(exclusion) if matches!(exclusion.reason(), ExclusionReason::PartialRecognition)
    ));
}

#[test]
fn masking_failure_refuses_to_emit() {
    let result = PrivacyGate::new(recall()).prepare(
        image_input_with(Arc::new(ImageMissingGeometryRecognizer)),
        &MissingGeometryOcr,
        &MissingGeometryOcr,
    );

    assert!(matches!(
        result,
        Err(exclusion) if matches!(exclusion.reason(), ExclusionReason::Masking(_))
    ));
}

#[test]
fn masked_recognition_without_exact_image_provenance_refuses_to_emit() {
    let result = PrivacyGate::new(recall()).prepare(
        image_input_with(Arc::new(ImageUnboundMaskedRecognizer)),
        &CompleteOcr,
        &CompleteVision,
    );

    assert!(matches!(
        result,
        Err(exclusion)
            if matches!(
                exclusion.reason(),
                ExclusionReason::Masking(qaptr_privacy::MaskError::MissingImageProvenance)
            )
    ));
}

#[test]
fn image_without_verification_recognizer_refuses_to_emit() {
    let input = PreparationInput::new(capture("missing-verifier"), safe_context())
        .with_image(
            Image::solid(8, 8, [255, 255, 255]).expect("test image"),
            ImageOrientation::Up,
        )
        .allow_image();
    let result = PrivacyGate::new(recall()).prepare(input, &CompleteOcr, &CompleteVision);

    assert!(matches!(
        result,
        Err(exclusion)
            if matches!(
                exclusion.reason(),
                ExclusionReason::Masking(qaptr_privacy::MaskError::MissingVerificationRecognizer)
            )
    ));
}

#[test]
fn sanitization_failure_refuses_to_emit() {
    let context = ContextSnapshot::new(
        Some("Safari".to_owned()),
        Some("unsafe\u{0000}title".to_owned()),
        None,
        None,
    );
    let result = PrivacyGate::new(recall()).prepare(
        PreparationInput::new(capture("unsafe-context"), context),
        &CompleteOcr,
        &CompleteVision,
    );

    assert!(matches!(
        result,
        Err(exclusion) if matches!(exclusion.reason(), ExclusionReason::Sanitization(_))
    ));
}

#[test]
fn deadline_failure_refuses_to_emit() {
    let gate = PrivacyGate::with_budget(recall(), Duration::ZERO);
    let result = gate.prepare(
        PreparationInput::new(capture("deadline"), safe_context()),
        &CompleteOcr,
        &CompleteVision,
    );

    assert!(matches!(
        result,
        Err(exclusion) if matches!(exclusion.reason(), ExclusionReason::Timeout { stage: PreparationStage::Recognition, budget, .. } if *budget == Duration::ZERO)
    ));
}

#[test]
fn passing_payload_contains_sanitization_and_coverage_proof() {
    let context = ContextSnapshot::new(
        Some("Safari".to_owned()),
        Some("email fixture.email@example.test password=fixture-password".to_owned()),
        None,
        None,
    );
    let input = PreparationInput::new(capture("proof"), context)
        .with_image(
            Image::solid(8, 8, [255, 255, 255]).expect("test image"),
            ImageOrientation::Up,
        )
        .with_image_recognizer(Arc::new(ImageCompleteRecognizer))
        .allow_image();
    let payload = PrivacyGate::new(honest_recall())
        .prepare(input, &CompleteOcr, &CompleteVision)
        .expect("complete local pipeline should pass");

    assert_eq!(
        payload
            .context()
            .get(qaptr_privacy::ContextField::WindowTitle),
        Some("email [REDACTED_EMAIL] [REDACTED_CREDENTIAL]")
    );
    assert!(
        payload
            .proof()
            .sanitized_classes()
            .contains(&SensitiveClass::EmailAddress)
    );
    assert!(
        payload
            .proof()
            .sanitized_classes()
            .contains(&SensitiveClass::Credential)
    );
    assert_eq!(payload.proof().masked_region_count(), 2);
    assert_eq!(
        payload
            .proof()
            .coverage()
            .map(|proof| proof.detected_region_count()),
        Some(2)
    );
    assert_eq!(
        payload
            .masked_image()
            .map(|image| image.proof().detected_region_count()),
        Some(2)
    );
    assert_eq!(payload.proof().recall().ground_truth_count(), 6);
    assert_eq!(payload.proof().recall().matched_count(), 5);
    assert_eq!(payload.proof().recall().missed_indices(), &[5]);
    assert!((payload.proof().recall().recall() - (5.0 / 6.0)).abs() < f64::EPSILON);
    let verification = payload
        .proof()
        .coverage()
        .and_then(|proof| proof.recognition_verification())
        .expect("image coverage must carry rerun evidence");
    assert!(verification.has_no_residual_detected_regions());
}

#[test]
fn image_is_not_emitted_without_explicit_opt_in() {
    let input = PreparationInput::new(capture("no-image"), safe_context()).with_image(
        Image::solid(8, 8, [255, 255, 255]).expect("test image"),
        ImageOrientation::Up,
    );
    let payload = PrivacyGate::new(recall())
        .prepare(input, &CompleteOcr, &CompleteVision)
        .expect("context-only preparation should pass");

    assert!(payload.masked_image().is_none());
    assert!(payload.proof().coverage().is_none());
}

#[test]
fn one_excluded_capture_leaves_four_prepared_and_one_notice() {
    let gate = PrivacyGate::new(recall());
    let mut prepared = 0;
    let mut excluded = Vec::new();
    for index in 0..5 {
        let context = if index == 2 {
            ContextSnapshot::new(Some("bad\u{0000}context".to_owned()), None, None, None)
        } else {
            safe_context()
        };
        let result = gate.prepare(
            PreparationInput::new(capture(&format!("capture-{index}")), context),
            &CompleteOcr,
            &CompleteVision,
        );
        match result {
            Ok(_) => prepared += 1,
            Err(exclusion) => excluded.push(exclusion),
        }
    }

    assert_eq!(prepared, 4);
    assert_eq!(excluded.len(), 1);
}

#[test]
fn measured_gate_pipeline_stays_within_full_budget() {
    let gate = PrivacyGate::new(recall());
    let mut samples = Vec::with_capacity(24);
    for _ in 0..24 {
        let started = Instant::now();
        gate.prepare(image_input(), &CompleteOcr, &CompleteVision)
            .expect("deterministic fixture should prepare");
        samples.push(started.elapsed());
    }
    samples.sort_unstable();
    let median = samples[samples.len() / 2];
    let peak = samples.last().copied().expect("measurement has samples");
    println!(
        "U12 core preparation: samples={}, median={:.3} ms, peak={:.3} ms, budget={} ms",
        samples.len(),
        median.as_secs_f64() * 1_000.0,
        peak.as_secs_f64() * 1_000.0,
        FULL_PREPARATION_BUDGET.as_millis()
    );
    assert!(median < FULL_PREPARATION_BUDGET);
}
