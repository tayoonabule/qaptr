# Qaptr product truth

## What Qaptr is

Qaptr is a local-first Rust system that takes occasional screenshots, keeps
source material private on the device, and turns approved context into useful
structured notes.

## Product promises

- Sensitive material is excluded before a capture is sealed.
- OCR and PII recognition run locally.
- Privacy preparation fails closed when recognition, masking, sanitization, or
  budget checks do not pass.
- Provider requests are explicit and receive only approved, redacted material.
- Provider credentials remain outside readable settings and exported state.
- The website explains the product and collects an email. It does not pretend to
  be the local processing runtime.

## Product boundaries

- Rust macOS adapters own local image recognition and credential integration.
- `qaptr-privacy` owns recognition, masking, sanitization, and emission policy.
- `qaptr-vault` owns encrypted capture bundles and retention.
- `qaptr-workflow` owns bounded analysis and export models.
- `qaptr-ffi` is the narrow capture/vault boundary.

The former native Swift applications and macOS review UI are intentionally not
part of this clean-start branch.
