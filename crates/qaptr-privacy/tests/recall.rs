//! Labeled-corpus recall evidence tests for U10.

use qaptr_domain::NormalizedRect;
use qaptr_privacy::{
    DetectionKind, ImageOrientation, MappedDetection, map_normalized_rect, measure_recall,
    measure_recall_with_threshold,
};

fn detection(kind: DetectionKind, x: f32, y: f32) -> MappedDetection {
    let normalized = NormalizedRect::new(x, y, 0.2, 0.2).expect("fixture geometry is valid");
    let rect = map_normalized_rect(normalized, 100, 100, ImageOrientation::Up)
        .expect("fixture mapping should succeed");
    MappedDetection::new(kind, rect)
}

#[test]
fn corpus_recall_records_a_known_recognizer_miss() {
    let truth = [
        detection(DetectionKind::Text, 0.1, 0.1),
        detection(DetectionKind::Face, 0.6, 0.6),
    ];
    let detected = [detection(DetectionKind::Text, 0.1, 0.1)];
    let report = measure_recall(&truth, &detected).expect("recall should succeed");

    assert_eq!(report.ground_truth_count(), 2);
    assert_eq!(report.matched_count(), 1);
    assert_eq!(report.missed_indices(), &[1]);
    assert_eq!(report.missed_kinds(&truth), vec![DetectionKind::Face]);
}

#[test]
fn recall_threshold_is_explicit_and_deterministic() {
    let truth = [detection(DetectionKind::Barcode, 0.1, 0.1)];
    let detected = [detection(DetectionKind::Barcode, 0.2, 0.1)];
    let report =
        measure_recall_with_threshold(&truth, &detected, 0.5).expect("recall should succeed");
    assert!(!report.is_complete());
    assert_eq!(report.iou_threshold(), 0.5);
}
