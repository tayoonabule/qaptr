use std::sync::Arc;

use qaptr_domain::CaptureId;
use qaptr_domain::ports::{ContextSnapshot, OcrResult, VisionResult};
use qaptr_domain::testing::{InMemoryOcr, InMemoryVision};
use qaptr_privacy::{
    Image, ImageOrientation, ImageRecognizer, PreparationInput, PreparedPayload, PrivacyGate,
    RecognitionResult, measure_recall,
};

#[derive(Debug)]
struct NoResidualImageRecognizer;

impl ImageRecognizer for NoResidualImageRecognizer {
    fn recognize_image(&self, _image: &Image) -> qaptr_domain::Result<RecognitionResult> {
        Ok(RecognitionResult::new(
            OcrResult::default(),
            VisionResult::default(),
        ))
    }
}

pub fn prepared_payload(with_image: bool) -> PreparedPayload {
    let input = PreparationInput::new(
        CaptureId::new("openrouter-contract").expect("test capture id is valid"),
        ContextSnapshot::new(Some("sanitized context".to_owned()), None, None, None),
    );
    let input = if with_image {
        input
            .with_image(
                Image::solid(8, 8, [255, 255, 255]).expect("test image is valid"),
                ImageOrientation::Up,
            )
            .with_image_recognizer(Arc::new(NoResidualImageRecognizer))
            .allow_image()
    } else {
        input
    };
    PrivacyGate::new(measure_recall(&[], &[]).expect("empty recall fixture is valid"))
        .prepare(
            input,
            &InMemoryOcr::ready(OcrResult::default()),
            &InMemoryVision::ready(VisionResult::default()),
        )
        .expect("privacy gate should prepare the test payload")
}
