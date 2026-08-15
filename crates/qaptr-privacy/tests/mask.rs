//! Pixel-level acceptance tests for irreversible U10 masking.

use qaptr_domain::NormalizedRect;
use qaptr_domain::ports::{OcrResult, VisionResult};
use qaptr_privacy::{
    CoverageError, DetectionKind, DetectionSet, Image, ImageOrientation, MASK_COLOR,
    MappedDetection, MaskError, RecognitionResult, map_normalized_rect, map_recognized_detections,
    mask_image,
};

fn detection(kind: DetectionKind, x: f32, y: f32, width: f32, height: f32) -> MappedDetection {
    let normalized = NormalizedRect::new(x, y, width, height).expect("fixture geometry is valid");
    let rect = map_normalized_rect(normalized, 10, 10, ImageOrientation::Up)
        .expect("fixture mapping should succeed");
    MappedDetection::new(kind, rect)
}

fn assert_rect_is_masked(image: &Image, detection: MappedDetection) {
    let rect = detection.rect();
    for y in rect.y()..rect.y() + rect.height() {
        for x in rect.x()..rect.x() + rect.width() {
            assert_eq!(image.pixel(x, y), Some(MASK_COLOR), "pixel ({x}, {y})");
        }
    }
}

#[test]
fn every_detected_region_is_covered_in_output_pixels() {
    let source = Image::solid(10, 10, [240, 241, 242]).expect("fixture image should be valid");
    let detections = [
        detection(DetectionKind::Text, 0.1, 0.1, 0.2, 0.2),
        detection(DetectionKind::Face, 0.6, 0.5, 0.2, 0.2),
        detection(DetectionKind::Barcode, 0.3, 0.7, 0.2, 0.1),
    ];
    let detection_set = DetectionSet::for_image(&source, detections.to_vec());
    let masked = mask_image(&source, &detection_set).expect("masking should succeed");

    for detection in detections {
        assert_rect_is_masked(masked.image(), detection);
    }
    assert_eq!(masked.image().pixel(9, 9), Some([240, 241, 242]));
    assert!(masked.verify(&detection_set).is_ok());
}

#[test]
fn coverage_proof_is_verifiable_against_detection_set_and_pixels() {
    let source = Image::solid(10, 10, [31, 32, 33]).expect("fixture image should be valid");
    let detections = [detection(DetectionKind::Text, 0.2, 0.2, 0.2, 0.2)];
    let detection_set = DetectionSet::for_image(&source, detections.to_vec());
    let masked = mask_image(&source, &detection_set).expect("masking should succeed");

    assert_eq!(masked.proof().detected_region_count(), 1);
    assert!(masked.proof().verify_detections(&detections).is_ok());
    assert!(masked.verify(&detection_set).is_ok());

    let tampered = Image::solid(10, 10, [31, 32, 33]).expect("fixture image should be valid");
    assert!(masked.proof().verify(&tampered, &detection_set).is_err());
}

#[test]
fn edge_touching_detection_is_fully_covered_without_writing_outside_image() {
    let source = Image::solid(10, 10, [200, 201, 202]).expect("fixture image should be valid");
    let edge = detection(DetectionKind::Face, 0.0, 0.8, 0.2, 0.2);
    let detection_set = DetectionSet::for_image(&source, vec![edge]);
    let masked = mask_image(&source, &detection_set).expect("edge masking should succeed");

    assert_rect_is_masked(masked.image(), edge);
    assert_eq!(masked.image().pixel(3, 0), Some([200, 201, 202]));
    assert!(masked.verify(&detection_set).is_ok());
}

#[test]
fn overlapping_detections_leave_no_gap_and_are_each_proven() {
    let source = Image::solid(10, 10, [180, 181, 182]).expect("fixture image should be valid");
    let left = detection(DetectionKind::Text, 0.1, 0.2, 0.3, 0.2);
    let right = detection(DetectionKind::Text, 0.3, 0.2, 0.3, 0.2);
    let detection_set = DetectionSet::for_image(&source, vec![left, right]);
    let masked = mask_image(&source, &detection_set).expect("overlap masking should succeed");

    for x in left.rect().x()..right.rect().x() + right.rect().width() {
        for y in left.rect().y()..left.rect().y() + left.rect().height() {
            assert_eq!(
                masked.image().pixel(x, y),
                Some(MASK_COLOR),
                "pixel ({x}, {y})"
            );
        }
    }
    assert_eq!(masked.proof().detected_region_count(), 2);
    assert!(masked.verify(&detection_set).is_ok());
}

#[test]
fn masking_is_deterministic_for_same_pixels_and_detections() {
    let source = Image::solid(10, 10, [90, 91, 92]).expect("fixture image should be valid");
    let detections = [
        detection(DetectionKind::Barcode, 0.0, 0.0, 0.2, 0.2),
        detection(DetectionKind::Face, 0.1, 0.1, 0.3, 0.3),
    ];
    let detection_set = DetectionSet::for_image(&source, detections.to_vec());
    let first = mask_image(&source, &detection_set).expect("first masking should succeed");
    let second = mask_image(&source, &detection_set).expect("second masking should succeed");

    assert_eq!(first, second);
    assert_eq!(first.image().pixels(), second.image().pixels());
}

#[test]
fn no_detections_preserves_pixels_and_still_returns_a_valid_proof() {
    let source = Image::solid(3, 2, [70, 71, 72]).expect("fixture image should be valid");
    let detections = DetectionSet::for_image(&source, Vec::new());
    let masked = mask_image(&source, &detections).expect("no-op masking should succeed");

    assert_eq!(masked.image(), &source);
    assert!(masked.proof().entries().is_empty());
    assert!(masked.verify(&detections).is_ok());
}

#[test]
fn masking_refuses_detection_set_from_different_image_bytes() {
    let source = Image::solid(2, 2, [1, 2, 3]).expect("fixture image should be valid");
    let different = Image::solid(2, 2, [4, 5, 6]).expect("fixture image should be valid");
    let detection = detection(DetectionKind::Text, 0.0, 0.0, 0.2, 0.2);
    let detection_set = DetectionSet::for_image(&source, vec![detection]);

    let result = mask_image(&different, &detection_set);
    assert!(matches!(result, Err(MaskError::ImageHashMismatch { .. })));
}

#[test]
fn image_bound_recognition_refuses_mapping_onto_different_image_bytes() {
    let source = Image::solid(10, 10, [21, 22, 23]).expect("fixture image should be valid");
    let different = Image::solid(10, 10, [24, 25, 26]).expect("fixture image should be valid");
    let recognition = RecognitionResult::for_image(
        qaptr_domain::ports::ocr::OcrResult::default(),
        qaptr_domain::ports::vision::VisionResult::default(),
        &source,
    );

    let result =
        qaptr_privacy::map_recognized_detections(&recognition, &different, ImageOrientation::Up);
    assert!(matches!(result, Err(MaskError::ImageHashMismatch { .. })));
}

#[test]
fn capture_bound_recognition_cannot_enter_image_masking() {
    let image = Image::solid(2, 2, [1, 2, 3]).expect("fixture image should be valid");
    let recognition = RecognitionResult::new(
        OcrResult::default(),
        VisionResult::default(),
        &qaptr_domain::CaptureId::new("capture-bound").expect("fixture capture id"),
    );

    assert!(matches!(
        map_recognized_detections(&recognition, &image, ImageOrientation::Up),
        Err(MaskError::MissingImageProvenance)
    ));
}

#[test]
fn masked_output_verification_records_no_residual_regions() {
    let source = Image::solid(10, 10, [10, 11, 12]).expect("fixture image should be valid");
    let detection = detection(DetectionKind::Text, 0.2, 0.2, 0.2, 0.2);
    let detections = DetectionSet::for_image(&source, vec![detection]);
    let mut masked = mask_image(&source, &detections).expect("masking should succeed");
    let rerun = DetectionSet::for_image(masked.image(), Vec::new());

    masked
        .verify_masked_recognition(&rerun)
        .expect("empty rerun should prove no residual region");
    let verification = masked
        .proof()
        .recognition_verification()
        .expect("verification evidence should be recorded");
    assert!(verification.has_no_residual_detected_regions());
    assert_eq!(verification.rerun_detected_region_count(), 0);
}

#[test]
fn masked_output_verification_rejects_a_recognizable_original_region() {
    let source = Image::solid(10, 10, [13, 14, 15]).expect("fixture image should be valid");
    let detection = detection(DetectionKind::Text, 0.2, 0.2, 0.2, 0.2);
    let detections = DetectionSet::for_image(&source, vec![detection]);
    let mut masked = mask_image(&source, &detections).expect("masking should succeed");
    let rerun = DetectionSet::for_image(masked.image(), vec![detection]);

    assert!(matches!(
        masked.verify_masked_recognition(&rerun),
        Err(CoverageError::ResidualDetection { count: 1 })
    ));
}
