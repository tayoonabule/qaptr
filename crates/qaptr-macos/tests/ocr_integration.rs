//! On-device Vision integration tests for U9.

#![cfg(target_os = "macos")]

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use qaptr_domain::ports::ocr::OcrPort;
use qaptr_domain::ports::vision::{VisionKind, VisionPort};
use qaptr_domain::{CaptureId, DomainError};
use qaptr_macos::{MacOcr, MacVision};

fn fixture_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../qaptr-privacy/fixtures/ocr")
}

fn capture(name: &str) -> CaptureId {
    CaptureId::new(name).expect("fixture capture id is valid")
}

#[test]
fn known_text_fixture_yields_text_and_geometry() {
    let result = MacOcr::new(fixture_root())
        .recognize(&capture("text"))
        .expect("Vision OCR should succeed")
        .into_inner();
    assert!(result.regions().iter().any(|region| {
        region.text().contains("alice@example.com") && region.geometry().is_some()
    }));
}

#[test]
fn no_text_and_single_color_images_are_empty_successes() {
    let adapter = MacOcr::new(fixture_root());
    for name in ["no_text", "single_color"] {
        let result = adapter
            .recognize(&capture(name))
            .expect("an image without text is not an OCR error")
            .into_inner();
        assert!(result.regions().is_empty(), "fixture {name} produced OCR");
    }
}

#[test]
fn barcode_fixture_yields_a_geometry_bearing_barcode_finding() {
    let result = MacVision::new(fixture_root())
        .detect(&capture("qr"))
        .expect("Vision detection should succeed")
        .into_inner();
    assert!(
        result.findings().iter().any(|finding| {
            finding.kind() == VisionKind::Barcode && finding.geometry().is_some()
        })
    );
}

#[test]
fn repeated_recognition_is_deterministic() {
    let adapter = MacOcr::new(fixture_root());
    let first = adapter
        .recognize(&capture("text"))
        .expect("first recognition should succeed");
    let second = adapter
        .recognize(&capture("text"))
        .expect("second recognition should succeed");
    assert_eq!(first, second);
}

#[test]
fn timeout_is_a_typed_timeout_not_an_empty_result() {
    let path = std::env::temp_dir().join(format!(
        "qaptr-u9-timeout-{}-{}.sh",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("test clock should be after epoch")
            .as_nanos()
    ));
    fs::write(&path, "#!/bin/sh\nwhile true; do :; done\n")
        .expect("timeout helper should be writable");
    let mut permissions = fs::metadata(&path)
        .expect("timeout helper metadata should exist")
        .permissions();
    permissions.set_mode(0o755);
    fs::set_permissions(&path, permissions).expect("timeout helper should be executable");

    let result = MacOcr::with_helper(fixture_root(), &path, Duration::from_millis(10))
        .recognize(&capture("text"));
    let _ = fs::remove_file(&path);
    assert_eq!(result, Err(DomainError::TimedOut { operation: "ocr" }));
}

#[test]
fn human_labeled_corpus_reports_recall_and_misses_honestly() {
    let root = fixture_root();
    let ocr = MacOcr::new(&root);
    let vision = MacVision::new(&root);
    let labels = fs::read_to_string(root.join("ground_truth.csv"))
        .expect("human-labeled corpus should be present");
    let mut total = 0_u32;
    let mut detected = 0_u32;
    let mut misses = Vec::new();

    for line in labels
        .lines()
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
    {
        let fields: Vec<&str> = line.splitn(7, ',').collect();
        assert_eq!(fields.len(), 7, "ground-truth row must have seven fields");
        let image = fields[0]
            .strip_suffix(".png")
            .expect("image label has PNG suffix");
        let kind = fields[1];
        let expected = fields[2];
        if kind == "none" {
            let ocr_result = ocr
                .recognize(&capture(image))
                .expect("negative OCR fixture should succeed")
                .into_inner();
            assert!(
                ocr_result.regions().is_empty(),
                "negative fixture produced text"
            );
            continue;
        }

        total += 1;
        let found = match kind {
            "text" => ocr
                .recognize(&capture(image))
                .expect("text fixture should recognize")
                .into_inner()
                .regions()
                .iter()
                .any(|region| region.text().contains(expected)),
            "barcode" => vision
                .detect(&capture(image))
                .expect("barcode fixture should detect")
                .into_inner()
                .findings()
                .iter()
                .any(|finding| finding.kind() == VisionKind::Barcode),
            other => panic!("unsupported ground-truth kind: {other}"),
        };
        if found {
            detected += 1;
        } else {
            misses.push(format!("{}:{kind}:{expected}", fields[0]));
        }
    }

    let recall = detected as f64 / total as f64;
    println!("U9 human-labeled recall: {detected}/{total} = {recall:.3}; misses: {misses:?}");
    assert!(total > 0, "corpus must contain positive labels");
}

#[test]
fn missing_fixture_is_a_typed_failure() {
    let result = MacOcr::new(fixture_root()).recognize(&capture("missing"));
    assert!(matches!(
        result,
        Err(DomainError::Failed {
            operation: "ocr",
            ..
        })
    ));
}

#[test]
fn recognition_budget_is_measured_on_the_committed_fixture_session() {
    let adapter = MacOcr::new(fixture_root());
    let fixture_names = ["text", "rotated", "no_text", "single_color", "low_contrast"];
    let mut samples = Vec::with_capacity(24);
    for index in 0..24 {
        let name = fixture_names[index % fixture_names.len()];
        let started = Instant::now();
        adapter
            .recognize(&capture(name))
            .expect("fixture recognition should complete within the U9 deadline");
        samples.push(started.elapsed());
    }
    samples.sort_unstable();
    let median = samples[samples.len() / 2];
    let peak = samples.last().copied().expect("measurement has samples");
    println!(
        "U9 recognition budget: median={} ms, peak={} ms, samples={}",
        median.as_secs_f64() * 1_000.0,
        peak.as_secs_f64() * 1_000.0,
        samples.len()
    );
    assert!(
        median < Duration::from_millis(500),
        "U9 recognition median exceeded 500 ms: {median:?}"
    );
}
