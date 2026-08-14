//! Recall measurement for the recognizer-detected subset of privacy classes.
//!
//! Recall is deliberately separate from masking. Masking proves coverage of
//! reported detections; this module measures what a labeled corpus says the
//! recognizers failed to report.

use thiserror::Error;

use crate::mask::{DetectionKind, MappedDetection};

/// Default intersection-over-union threshold for matching detections to labels.
pub const DEFAULT_IOU_THRESHOLD: f64 = 0.5;

/// Measured recall against human-authored ground-truth regions.
#[derive(Clone, Debug, PartialEq)]
pub struct RecallReport {
    ground_truth_count: usize,
    matched_count: usize,
    missed_indices: Vec<usize>,
    iou_threshold: f64,
}

impl RecallReport {
    /// Returns the number of labeled regions in the corpus slice.
    pub const fn ground_truth_count(&self) -> usize {
        self.ground_truth_count
    }

    /// Returns the number of labeled regions matched by recognizer detections.
    pub const fn matched_count(&self) -> usize {
        self.matched_count
    }

    /// Returns the labeled-region indices not detected at the configured threshold.
    pub fn missed_indices(&self) -> &[usize] {
        &self.missed_indices
    }

    /// Returns the configured IoU matching threshold.
    pub const fn iou_threshold(&self) -> f64 {
        self.iou_threshold
    }

    /// Returns recall as a value from zero through one.
    pub fn recall(&self) -> f64 {
        if self.ground_truth_count == 0 {
            1.0
        } else {
            self.matched_count as f64 / self.ground_truth_count as f64
        }
    }

    /// Returns whether every labeled region was detected.
    pub fn is_complete(&self) -> bool {
        self.missed_indices.is_empty()
    }

    /// Returns detected-class counts for the labels that were missed.
    pub fn missed_kinds(&self, ground_truth: &[MappedDetection]) -> Vec<DetectionKind> {
        self.missed_indices
            .iter()
            .filter_map(|index| ground_truth.get(*index).map(|region| region.kind()))
            .collect()
    }
}

/// Measures recall using the default 0.5 IoU threshold.
pub fn measure_recall(
    ground_truth: &[MappedDetection],
    detections: &[MappedDetection],
) -> Result<RecallReport, RecallError> {
    measure_recall_with_threshold(ground_truth, detections, DEFAULT_IOU_THRESHOLD)
}

/// Measures recall using an explicit intersection-over-union threshold.
///
/// Each detection can match at most one labeled region. Matching also requires
/// the recognizer class to agree, so a face cannot satisfy a text label merely
/// by overlapping it.
pub fn measure_recall_with_threshold(
    ground_truth: &[MappedDetection],
    detections: &[MappedDetection],
    iou_threshold: f64,
) -> Result<RecallReport, RecallError> {
    if !(0.0..=1.0).contains(&iou_threshold) || !iou_threshold.is_finite() {
        return Err(RecallError::InvalidIouThreshold(iou_threshold));
    }
    for region in ground_truth.iter().chain(detections) {
        if region.rect().width() == 0 || region.rect().height() == 0 {
            return Err(RecallError::InvalidRegion);
        }
    }

    let mut used = vec![false; detections.len()];
    let mut matched_count = 0;
    let mut missed_indices = Vec::new();
    for (truth_index, truth) in ground_truth.iter().enumerate() {
        let mut best: Option<(usize, f64)> = None;
        for (detection_index, detection) in detections.iter().enumerate() {
            if used[detection_index] || truth.kind() != detection.kind() {
                continue;
            }
            let overlap = iou(truth, detection);
            if overlap >= iou_threshold
                && best.is_none_or(|(_, best_overlap)| overlap > best_overlap)
            {
                best = Some((detection_index, overlap));
            }
        }
        if let Some((detection_index, _)) = best {
            used[detection_index] = true;
            matched_count += 1;
        } else {
            missed_indices.push(truth_index);
        }
    }
    Ok(RecallReport {
        ground_truth_count: ground_truth.len(),
        matched_count,
        missed_indices,
        iou_threshold,
    })
}

fn iou(left: &MappedDetection, right: &MappedDetection) -> f64 {
    let left_rect = left.rect();
    let right_rect = right.rect();
    let intersection_left = left_rect.x().max(right_rect.x());
    let intersection_top = left_rect.y().max(right_rect.y());
    let intersection_right =
        (left_rect.x() + left_rect.width()).min(right_rect.x() + right_rect.width());
    let intersection_bottom =
        (left_rect.y() + left_rect.height()).min(right_rect.y() + right_rect.height());
    if intersection_left >= intersection_right || intersection_top >= intersection_bottom {
        return 0.0;
    }
    let intersection = u64::from(intersection_right - intersection_left)
        * u64::from(intersection_bottom - intersection_top);
    let left_area = u64::from(left_rect.width()) * u64::from(left_rect.height());
    let right_area = u64::from(right_rect.width()) * u64::from(right_rect.height());
    let union = left_area + right_area - intersection;
    intersection as f64 / union as f64
}

/// Errors raised while calculating a labeled recall report.
#[derive(Clone, Debug, Error, PartialEq)]
pub enum RecallError {
    /// The IoU threshold is not a finite fraction.
    #[error("IoU threshold must be finite and between 0 and 1, got {0}")]
    InvalidIouThreshold(f64),
    /// A corpus region has no pixels.
    #[error("recall corpus contains a zero-sized region")]
    InvalidRegion,
}

#[cfg(test)]
mod tests {
    use super::{measure_recall, measure_recall_with_threshold};
    use crate::ImageOrientation;
    use crate::map_normalized_rect;
    use crate::mask::{DetectionKind, MappedDetection};
    use qaptr_domain::NormalizedRect;

    fn detection(kind: DetectionKind, x: f32, y: f32) -> MappedDetection {
        let normalized = NormalizedRect::new(x, y, 0.2, 0.2).expect("fixture geometry is valid");
        let rect = map_normalized_rect(normalized, 100, 100, ImageOrientation::Up)
            .expect("fixture mapping is valid");
        MappedDetection::new(kind, rect)
    }

    #[test]
    fn recall_reports_known_missed_regions_instead_of_hiding_them() {
        let truth = [
            detection(DetectionKind::Text, 0.1, 0.1),
            detection(DetectionKind::Face, 0.6, 0.6),
        ];
        let found = [detection(DetectionKind::Text, 0.1, 0.1)];
        let report = measure_recall(&truth, &found).expect("recall should calculate");
        assert_eq!(report.ground_truth_count(), 2);
        assert_eq!(report.matched_count(), 1);
        assert_eq!(report.missed_indices(), &[1]);
        assert!((report.recall() - 0.5).abs() < f64::EPSILON);
        assert_eq!(report.missed_kinds(&truth), vec![DetectionKind::Face]);
    }

    #[test]
    fn empty_corpus_has_perfect_vacuous_recall() {
        let report = measure_recall(&[], &[]).expect("empty corpus should calculate");
        assert_eq!(report.recall(), 1.0);
        assert!(report.is_complete());
    }

    #[test]
    fn invalid_threshold_is_rejected() {
        let error = measure_recall_with_threshold(&[], &[], 1.1).expect_err("threshold is invalid");
        assert!(error.to_string().contains("between 0 and 1"));
    }
}
