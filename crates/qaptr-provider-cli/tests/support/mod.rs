use qaptr_domain::ports::{ContextSnapshot, OcrResult, VisionResult};
use qaptr_domain::testing::{InMemoryOcr, InMemoryVision};
use qaptr_domain::CaptureId;
use qaptr_privacy::{
    measure_recall, Image, ImageOrientation, PreparationInput, PreparedPayload, PrivacyGate,
};

pub fn prepared_payload(with_image: bool) -> PreparedPayload {
    let input = PreparationInput::new(
        CaptureId::new("provider-cli-contract").expect("test capture id is valid"),
        ContextSnapshot::new(Some("sanitized context".to_owned()), None, None, None),
    );
    let input = if with_image {
        input
            .with_image(
                Image::solid(8, 8, [255, 255, 255]).expect("test image is valid"),
                ImageOrientation::Up,
            )
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
