# Graph Report - qaptr  (2026-08-15)

## Corpus Check
- 177 files · ~85,432 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2300 nodes · 4907 edges · 152 communities (125 shown, 27 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 94 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `36b257c5`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Self
- tests/analyze.rs
- Duration
- DetailedCaptureProfile
- classes.rs
- qaptr-provider-openrouter/tests/contract.rs
- src/analyze.rs
- scripts
- CodexAdapter
- fs.rs
- Vault
- GenerationId
- waitlist.ts
- Sendable
- RustVaultAPI
- BundleMetadata
- LoginItemState
- MappedDetection
- Self
- CapabilityDescriptor
- ObservationRecord
- Implementation Units
- swiftui-shell/main.swift
- CliInvocation
- PortOutcome
- RecallReport
- .prepare
- .capture
- MacosError
- CliRuntimeError
- PreparationProof
- .new
- CoverageProof
- ConsentRequest
- CaptureEvent
- ContextSnapshot
- ProviderVersion
- CliOutput
- Store
- vault.rs
- ProviderDescriptor
- RawProviderResponse
- enforce_retention
- ExecutablePath
- ProviderRequestError
- FakeProvider
- qaptr-vault/src/lib.rs
- QaptrHelper/main.swift
- tauri.conf.json
- CaptureSample
- seal_if_allowed
- ClaudeAdapter
- ProviderError
- .new
- src/permissions.rs
- .new
- NoticeRecord
- qaptr-store/src/lib.rs
- tests/gate.rs
- store.rs
- compilerOptions
- ports.rs
- map_normalized_rect
- waitlist.test.ts
- HelperApplication
- .read_value
- FakeExecutor
- .new
- tests/retention.rs
- Team Handoff: Weekly exception review
- Standard Operating Procedure: Weekly exception review
- Qaptr v1
- ScreenCapture.swift
- CaptureCoreError
- Automation Procedure: Weekly exception review
- Onboarding Guide: Weekly exception review
- qaptr-domain
- CapturedFrame
- FakeHttp
- CredentialKey
- Planning Contract
- sign.sh
- ContextSampler.swift
- U4 capture-cost prototype gate
- capture_soak.sh
- VisionResult
- mask_image
- RuntimeLimits
- qaptr-store/src/schema.rs
- MemoryCredentials
- U9 OCR and Vision measurement
- U3 shell measurement gate
- FakeProvider
- PortOutcome<T>
- Website design rationale (U21)
- U22 packaging evidence
- Result
- measure.py
- U12 full preparation measurement
- main.rs
- MacVision
- Product Contract
- migrations/mod.rs
- Qaptr capture helper
- release.sh
- MacOcr
- dmg.sh
- notarize.sh
- reproducibility.sh
- build_app.sh
- Package.swift
- swiftui-shell/build.sh
- tauri-shell/build.sh
- qaptr-tauri-shell-probe
- Decoder
- .run
- Confidence
- Working in this repository
- runtime
- PermissionState
- NormalizedRect
- RecognitionResult
- Harness
- 0001_initial.sql
- 0001_waitlist.sql
- 0002_notices.sql
- ProviderDetection
- Error
- PortResult
- TempRoot
- .into_result
- C
- Debug
- Formatter
- K
- O
- V
- Vec
- Cell
- Drop
- HashMap
- Mutex
- Path
- PathBuf

## God Nodes (most connected - your core abstractions)
1. `CliRuntimeError` - 38 edges
2. `ProviderError` - 33 edges
3. `CliOutput` - 29 edges
4. `Vault` - 28 edges
5. `MacosError` - 27 edges
6. `CredentialKey` - 27 edges
7. `CredentialValue` - 27 edges
8. `Duration` - 26 edges
9. `Implementation Units` - 25 edges
10. `ConfidenceAssessment` - 24 edges

## Surprising Connections (you probably didn't know these)
- `empty_detection_set_is_a_valid_honest_proof()` --calls--> `mask_image()`  [INFERRED]
  crates/qaptr-privacy/src/coverage.rs → crates/qaptr-privacy/src/mask.rs
- `QaptrSwiftUIShellProbe` --implements--> `App`  [EXTRACTED]
  bench/probes/swiftui-shell/main.swift → web/src/env.d.ts
- `HelperApplication` --calls--> `PointInTimeContextSampler`  [INFERRED]
  apps/helper/Sources/QaptrHelper/main.swift → apps/helper/Sources/QaptrHelper/ContextSampler.swift
- `recall()` --calls--> `measure_recall()`  [INFERRED]
  crates/qaptr-workflow/tests/analyze.rs → crates/qaptr-privacy/src/recall.rs
- `map_recognized_detections()` --calls--> `map_normalized_rect()`  [INFERRED]
  crates/qaptr-privacy/src/mask.rs → crates/qaptr-privacy/src/recognize.rs

## Import Cycles
- 2-file cycle: `crates/qaptr-domain/src/testing/doubles.rs -> crates/qaptr-domain/src/testing/mod.rs -> crates/qaptr-domain/src/testing/doubles.rs`

## Communities (152 total, 27 thin omitted)

### Community 0 - "Self"
Cohesion: 0.05
Nodes (54): Artifact, ConfidenceAssessment, DecisionAlternative, DecisionPoint, optional_text(), Provenance, required_text(), CaptureId (+46 more)

### Community 1 - "tests/analyze.rs"
Cohesion: 0.28
Nodes (21): ContextSnapshot, declined_consent_keeps_preparation_local(), failure(), fixed_clock_makes_observation_creation_deterministic(), interruption_discards_staged_observations_for_a_clean_resume(), observations_are_scalar_summaries_with_provider_confidence_unchanged(), opened_bundle_is_consumed_before_gate_preparation(), privacy_gate_refusal_skips_provider_entirely() (+13 more)

### Community 2 - "Duration"
Cohesion: 0.15
Nodes (6): ByteSize, Duration, Error, Result, Self, StdDuration

### Community 3 - "DetailedCaptureProfile"
Cohesion: 0.20
Nodes (9): CaptureProfileLifecycle, CaptureProfileState, DetailedCaptureProfile, ProfileError, C, Option, Result, Self (+1 more)

### Community 4 - "classes.rs"
Cohesion: 0.07
Nodes (53): assignment_finding(), classes_from_findings(), detect_findings(), finding_order(), is_placeholder(), is_token_edge(), looks_like_address(), looks_like_api_key() (+45 more)

### Community 5 - "qaptr-provider-openrouter/tests/contract.rs"
Cohesion: 0.19
Nodes (13): adapter(), credential_port_is_read_only_for_the_adapter(), FakeCredentials, gate_routes_openrouter_to_the_shared_normalized_shape(), image_request_is_refused_by_gate_before_http_transport(), malformed_output_is_typed_and_transport_failures_are_typed(), missing_key_is_not_authenticated_and_is_never_written(), rate_limit_is_a_typed_failure_without_partial_response() (+5 more)

### Community 6 - "src/analyze.rs"
Cohesion: 0.06
Nodes (50): C, CaptureRecord, AnalysisError, AnalysisReport, AnalysisRunner, AnalysisRunner<'a, C, O, V, A, D, P, K>, Cancellation, cancelled_report() (+42 more)

### Community 7 - "scripts"
Cohesion: 0.05
Nodes (38): astro, @astrojs/check, @astrojs/cloudflare, @axe-core/playwright, @cloudflare/workers-types, tsx, typescript, dependencies (+30 more)

### Community 8 - "CodexAdapter"
Cohesion: 0.13
Nodes (16): CodexAdapter, Arc, CliRuntime, Option, PathBuf, Self, add_support_path(), CliExecutor (+8 more)

### Community 9 - "fs.rs"
Cohesion: 0.09
Nodes (45): copy_string(), fail(), invalid_seal_leaves_no_readable_partial_bundle(), public_key_lookup_does_not_require_private_material(), qaptr_vault_create(), qaptr_vault_destroy(), qaptr_vault_last_error(), qaptr_vault_public_key() (+37 more)

### Community 10 - "Vault"
Cohesion: 0.17
Nodes (14): decrypt_member(), encrypt_member(), generation_credential_key(), C, CaptureId, Identity, Into, Path (+6 more)

### Community 11 - "GenerationId"
Cohesion: 0.13
Nodes (15): GenerationId, GenerationKeypair, GenerationPrivateKey, GenerationPublicKey, Debug, Display, Formatter, FromStr (+7 more)

### Community 12 - "waitlist.ts"
Cohesion: 0.09
Nodes (24): RFC-5322, astro/tsconfigs/strict, @cloudflare/workers-types, dist, node_modules, tests, checkRateLimit(), hashClientKey() (+16 more)

### Community 13 - "Sendable"
Cohesion: 0.10
Nodes (21): BundleSealer, CaptureCoordinator, ImageCapture, Lease, reducedBrowserHost(), SingleFlightGate, SingleInstanceLock, URL (+13 more)

### Community 14 - "RustVaultAPI"
Cohesion: 0.12
Nodes (20): RustVaultAPI, RustVaultSealer, Data, SampledContext, String, URL, VaultBridgeError, creationFailed (+12 more)

### Community 15 - "BundleMetadata"
Cohesion: 0.14
Nodes (15): BundleInput, BundleMetadata, OpenedBundle, PrivacyImage, CaptureId, Debug, FnOnce, Formatter (+7 more)

### Community 16 - "LoginItemState"
Cohesion: 0.12
Nodes (11): LoginItemPort, LoginItemState, InMemoryLoginItem, desired_state(), MacLoginItem, native_status(), PortResult, Result (+3 more)

### Community 17 - "MappedDetection"
Cohesion: 0.16
Nodes (17): detection_kind(), DetectionKind, expected_byte_len(), Image, image_rejects_wrong_buffer_size(), map_recognized_detections(), MappedDetection, MaskError (+9 more)

### Community 18 - "Self"
Cohesion: 0.13
Nodes (7): AccessibilityContextPort, InMemoryAccessibilityContext, InMemoryCapture, InMemoryOcr, InMemoryVision, Self, Response

### Community 19 - "CapabilityDescriptor"
Cohesion: 0.11
Nodes (8): Capability, CapabilityDescriptor, CapabilityRequirements, Display, Formatter, Option, Result, Self

### Community 20 - "ObservationRecord"
Cohesion: 0.19
Nodes (19): CaptureRecord, HistorySnapshot, load_captures(), load_observations(), load_snapshot(), load_workflows(), ObservationRecord, CaptureId (+11 more)

### Community 21 - "Implementation Units"
Cohesion: 0.08
Nodes (25): Implementation Units, U10. Masking and coverage proof, U11. Context sanitization, U12. Fail-closed privacy gate, U13. Provider adapter contract and capability gate, U14. Isolated subprocess runtime for CLI adapters, U15. OpenRouter and Claude CLI adapters, U16. Codex and Jcode adapters behind the gate (+17 more)

### Community 22 - "swiftui-shell/main.swift"
Cohesion: 0.13
Nodes (19): AppDelegate, ObservationSheet, .body, outputPath(), QaptrSwiftUIShellProbe, .body, recordScreenCapturePermission(), Notification (+11 more)

### Community 23 - "CliInvocation"
Cohesion: 0.15
Nodes (16): AtomicBool, Child, Command, CliInvocation, configure_process_group(), read_output(), Arc, Into (+8 more)

### Community 24 - "PortOutcome"
Cohesion: 0.24
Nodes (10): PortOutcome, OcrPort, VisionPort, CompleteOcr, CompleteVision, MissingGeometryOcr, PartialOcr, CaptureId (+2 more)

### Community 25 - "RecallReport"
Cohesion: 0.15
Nodes (14): detection(), empty_corpus_has_perfect_vacuous_recall(), invalid_threshold_is_rejected(), iou(), measure_recall(), measure_recall_with_threshold(), recall_reports_known_missed_regions_instead_of_hiding_them(), RecallError (+6 more)

### Community 26 - ".prepare"
Cohesion: 0.16
Nodes (12): ExclusionReason, PreparationInput, PreparationStage, PrivacyExclusion, PrivacyGate, CaptureId, O, Option (+4 more)

### Community 27 - ".capture"
Cohesion: 0.16
Nodes (17): CallbackResult, ScreenCaptureError, .description, displayUnavailable, encodingFailed, framework, timedOut, Data (+9 more)

### Community 28 - "MacosError"
Cohesion: 0.24
Nodes (18): MacosError, String, map_error(), bounded_message(), decode_base64(), decode_base64_bytes(), image_path(), parse_number() (+10 more)

### Community 29 - "CliRuntimeError"
Cohesion: 0.24
Nodes (18): ChildStdin, append_allow_literal(), append_allow_subpath(), append_deny_subpath(), append_path_rule(), CliRuntimeError, ensure_executable(), escape_profile_string() (+10 more)

### Community 30 - "PreparationProof"
Cohesion: 0.16
Nodes (11): MaskedImage, PreparationProof, PreparedPayload, BTreeSet, CaptureId, Debug, Formatter, Option (+3 more)

### Community 31 - ".new"
Cohesion: 0.17
Nodes (18): adapter_with_outputs(), claude_normalizes_through_the_same_gate_response_shape(), executable_discovery(), FakeExecutor, image_request_cannot_bypass_the_gate(), malformed_provider_output_is_a_typed_runtime_failure(), missing_cli_is_a_typed_not_installed_error(), old_cli_is_refused_by_the_shared_gate() (+10 more)

### Community 32 - "CoverageProof"
Cohesion: 0.13
Nodes (9): CoverageEntry, CoverageError, CoverageProof, empty_detection_set_is_a_valid_honest_proof(), proof_matches_mapped_detection_and_pixels(), Result, Self, Vec (+1 more)

### Community 33 - "ConsentRequest"
Cohesion: 0.20
Nodes (6): ConsentDecision, ConsentPort, ConsentRequest, ProviderId, Self, FakeConsent

### Community 34 - "CaptureEvent"
Cohesion: 0.13
Nodes (18): CaptureEvent, refusedOverlap, sealed, skippedCapture, skippedNoDisplays, skippedPermission, skippedSealing, SampledContext (+10 more)

### Community 35 - "ContextSnapshot"
Cohesion: 0.25
Nodes (6): ContextRequest, ContextSnapshot, CaptureId, Option, Self, String

### Community 36 - "ProviderVersion"
Cohesion: 0.17
Nodes (8): parse_version(), FromStr, Result, Self, VersionProbe, VersionProbeError, ProviderVersion, Err

### Community 37 - "CliOutput"
Cohesion: 0.24
Nodes (16): CliOutput, adapter(), discovery(), executable_directory(), FakeExecutor, image_request_is_refused_before_codex_executor_runs(), installed_codex_passes_real_detection(), malformed_codex_output_is_a_typed_runtime_failure() (+8 more)

### Community 38 - "Store"
Cohesion: 0.18
Nodes (9): Arc, CaptureId, FnOnce, Mutex, PathBuf, Result, T, Vec (+1 more)

### Community 39 - "vault.rs"
Cohesion: 0.22
Nodes (16): concurrent_seal_and_delete_leave_only_complete_or_absent_bundles(), destroying_generation_key_makes_all_generation_bundles_unreadable(), input(), keypair(), MemoryCredentials, partially_written_bundle_is_rejected_without_repair(), public_key_alone_cannot_open_a_bundle(), HashMap (+8 more)

### Community 40 - "ProviderDescriptor"
Cohesion: 0.12
Nodes (10): AuthenticationMode, ProviderDescriptor, ProviderEndpoint, ProviderGate, ProviderGate<A>, ProviderInvocation<'a>, ProviderLocation, A (+2 more)

### Community 41 - "RawProviderResponse"
Cohesion: 0.07
Nodes (43): find_response(), is_response_object(), raw_observation(), raw_response(), raw_workflow(), Option, Value, invalid_type() (+35 more)

### Community 42 - "enforce_retention"
Cohesion: 0.19
Nodes (12): enforce_retention(), RetentionBundle, RetentionError, RetentionPolicy, RetentionReport, C, CaptureId, K (+4 more)

### Community 43 - "ExecutablePath"
Cohesion: 0.16
Nodes (13): DiscoveryError, ExecutableDiscovery, is_executable(), Arc, Error, IntoIterator, Item, PathBuf (+5 more)

### Community 44 - "ProviderRequestError"
Cohesion: 0.24
Nodes (10): non_empty_context(), ProviderPayloadKind, ProviderRequest, ProviderRequestError, Formatter, Into, Result, Self (+2 more)

### Community 45 - "FakeProvider"
Cohesion: 0.19
Nodes (13): ProviderAdapter, each_handshake_failure_is_a_distinct_typed_error(), endpoint_and_existing_session_are_supported_without_cli_special_cases(), FakeProvider, handshake_accepts_authenticated_new_enough_provider(), image_capability_is_checked_during_handshake_when_requested(), image_work_is_refused_before_adapter_invocation(), malformed_output_is_a_typed_runtime_failure() (+5 more)

### Community 46 - "qaptr-vault/src/lib.rs"
Cohesion: 0.12
Nodes (14): FileLock, Drop, Error, String, VaultError, Reaper, Reaper<'vault, 'credentials, C>, ReapReport (+6 more)

### Community 47 - "QaptrHelper/main.swift"
Cohesion: 0.16
Nodes (14): HelperError, .description, invalidArgument, Options, QaptrHelperMain, Int, SampledContext, Self (+6 more)

### Community 48 - "tauri.conf.json"
Cohesion: 0.11
Nodes (17): app, security, windows, withGlobalTauri, build, frontendDist, bundle, active (+9 more)

### Community 49 - "CaptureSample"
Cohesion: 0.15
Nodes (9): CapturePort, CaptureRequest, CaptureSample, DisplayId, CaptureId, Into, Result, Self (+1 more)

### Community 50 - "seal_if_allowed"
Cohesion: 0.18
Nodes (11): CaptureDecision, ExclusionReason, ExclusionRules, PolicyError, BTreeSet, Into, Option, Result (+3 more)

### Community 51 - "ClaudeAdapter"
Cohesion: 0.24
Nodes (9): ClaudeAdapter, parse_auth_status(), Arc, CliRuntime, Error, Option, PathBuf, Result (+1 more)

### Community 52 - "ProviderError"
Cohesion: 0.12
Nodes (18): Result, JcodeAdapter, Arc, CliRuntime, Option, PathBuf, Result, Self (+10 more)

### Community 53 - ".new"
Cohesion: 0.24
Nodes (14): adapter(), executable_directory(), FakeExecutor, image_request_is_refused_before_jcode_executor_runs(), installed_jcode_passes_real_detection(), malformed_jcode_output_is_a_typed_runtime_failure(), missing_jcode_is_typed_not_installed(), old_jcode_is_refused_by_the_shared_gate() (+6 more)

### Community 54 - "src/permissions.rs"
Cohesion: 0.15
Nodes (18): Permission, accessibility_preflight(), auth_value_to_state(), MacPermissions, query_tcc_state(), request_accessibility(), request_screen_capture(), Into (+10 more)

### Community 55 - ".new"
Cohesion: 0.32
Nodes (5): Formatter, Into, Result, Self, String

### Community 56 - "NoticeRecord"
Cohesion: 0.21
Nodes (11): insert(), load(), NoticeReason, NoticeRecord, Connection, Into, Result, Self (+3 more)

### Community 57 - "qaptr-store/src/lib.rs"
Cohesion: 0.23
Nodes (13): AsRef, configure_writer(), open_reader(), Connection, Error, Path, Self, String (+5 more)

### Community 58 - "tests/gate.rs"
Cohesion: 0.33
Nodes (14): capture(), deadline_failure_refuses_to_emit(), honest_recall(), image_input(), image_is_not_emitted_without_explicit_opt_in(), masking_failure_refuses_to_emit(), measured_gate_pipeline_stays_within_full_budget(), one_excluded_capture_leaves_four_prepared_and_one_notice() (+6 more)

### Community 59 - "store.rs"
Cohesion: 0.28
Nodes (15): capture(), concurrent_readers_observe_consistent_snapshots_during_a_write(), crash_mid_write_child(), crash_mid_write_leaves_a_recoverable_database(), deleting_a_capture_keeps_observations_and_workflows(), migration_from_empty_produces_the_allowlisted_schema(), observation(), remove_directory() (+7 more)

### Community 60 - "compilerOptions"
Cohesion: 0.12
Nodes (15): a11y/**/*.ts, e2e/**/*.ts, helpers/**/*.ts, node, unit/**/*.ts, compilerOptions, allowImportingTsExtensions, module (+7 more)

### Community 61 - "ports.rs"
Cohesion: 0.20
Nodes (6): capture_double_simulates_complete_partial_denied_and_timeout(), capture_id(), capture_request(), capture_sample(), processing_and_context_doubles_simulate_partial_results(), CaptureId

### Community 62 - "map_normalized_rect"
Cohesion: 0.23
Nodes (5): ImageOrientation, map_normalized_rect(), PixelRect, rect(), transform_point()

### Community 63 - "waitlist.test.ts"
Cohesion: 0.21
Nodes (7): RFC-5737, main(), PAGES_TO_SCAN, DevServer, startDevServer(), webRoot, main()

### Community 64 - "HelperApplication"
Cohesion: 0.27
Nodes (4): HelperApplication, Notification, ScreenCaptureAdapter, DispatchSourceTimer

### Community 65 - ".read_value"
Cohesion: 0.22
Nodes (9): keychain_error(), MacCredentials, options_for(), Option, PortResult, Result, Self, PasswordOptions (+1 more)

### Community 66 - "FakeExecutor"
Cohesion: 0.24
Nodes (8): codex_and_jcode_normalize_to_the_same_response_shape(), directory(), FakeExecutor, Mutex, PathBuf, Result, Self, Vec

### Community 67 - ".new"
Cohesion: 0.18
Nodes (15): Clock, FixedClock, Self, SystemTime, SystemClock, a_second_start_is_rejected_without_stacking_or_extending_the_first_window(), detailed_profile_expires_automatically_at_its_bound(), ending_early_returns_to_sparse_mode_immediately() (+7 more)

### Community 68 - "tests/retention.rs"
Cohesion: 0.36
Nodes (10): a_reaper_pass_can_stop_between_generations_and_resume_without_half_deleted_bundles(), capture_record(), configure_generation(), excluded_application_never_creates_a_bundle_and_notice_has_no_capture_content(), excluded_window_never_creates_a_bundle(), expired_generation_is_unreadable_while_derived_history_survives(), input(), keypair() (+2 more)

### Community 69 - "Team Handoff: Weekly exception review"
Cohesion: 0.17
Nodes (11): 1. Open the source, 2. Review exceptions, Decisions and open questions, Evidence trail, Inputs the next person needs, Known variations, Observed sequence, Outputs to pass forward (+3 more)

### Community 70 - "Standard Operating Procedure: Weekly exception review"
Cohesion: 0.17
Nodes (11): 1. Open the source, 2. Review exceptions, Decision table, Exceptions and variations, Expected outputs, Observed tools, Procedure, Purpose and scope (+3 more)

### Community 71 - "Qaptr v1"
Cohesion: 0.29
Nodes (7): Appendix, Definition of Done, Goal Capsule, Open questions, Qaptr v1, Sources and research, Verification Contract

### Community 72 - "ScreenCapture.swift"
Cohesion: 0.20
Nodes (9): fail(), run(), String, ImageIO, Never, ScreenCaptureKit, UniformTypeIdentifiers, Vision (+1 more)

### Community 73 - "CaptureCoreError"
Cohesion: 0.29
Nodes (7): CaptureCoreError, captureFailed, invalidInterval, sealingFailed, CaptureInterval, TickPlanner, TimeInterval

### Community 74 - "Automation Procedure: Weekly exception review"
Cohesion: 0.18
Nodes (10): Automation boundary, Automation Procedure: Weekly exception review, Branching logic, Inputs, Known variations, Observed tool capabilities, Outputs, Procedure model (+2 more)

### Community 75 - "Onboarding Guide: Weekly exception review"
Cohesion: 0.18
Nodes (10): Before you begin, Guided walkthrough, Lesson 1: Open the source, Lesson 2: Review exceptions, Onboarding Guide: Weekly exception review, Source note, Tools and vocabulary, What you will learn (+2 more)

### Community 76 - "qaptr-domain"
Cohesion: 0.33
Nodes (11): qaptr-domain, qaptr-ffi, qaptr-macos, qaptr-policy, qaptr-privacy, qaptr-provider, qaptr-provider-cli, qaptr-provider-openrouter (+3 more)

### Community 77 - "CapturedFrame"
Cohesion: 0.31
Nodes (5): CapturedFrame, Data, Int, Int, String

### Community 78 - "FakeHttp"
Cohesion: 0.21
Nodes (11): Agent, HttpResponse, HttpTransport, OpenRouterHttpClient, Result, Self, String, TransportError (+3 more)

### Community 79 - "CredentialKey"
Cohesion: 0.17
Nodes (12): CredentialKey, CredentialPort, CredentialValue, Debug, InMemoryCredentials, Option, MemoryCredentials, HashMap (+4 more)

### Community 80 - "Planning Contract"
Cohesion: 0.20
Nodes (10): Architecture principles, Assumptions, Code Quality Contract, High-level technical design, Key technical decisions, Measurement protocol, Output structure, Ownership table (+2 more)

### Community 81 - "sign.sh"
Cohesion: 0.33
Nodes (8): audit_helper(), bundle_id(), plist_value(), sign.sh script, sign_bundles(), sign_macho_files(), usage(), verify_bundle()

### Community 83 - "ContextSampler.swift"
Cohesion: 0.25
Nodes (6): AppKit, ApplicationServices, PointInTimeContextSampler, SampledContext, String, NSRunningApplication

### Community 84 - "U4 capture-cost prototype gate"
Cohesion: 0.22
Nodes (8): Decision, Environment-change observations, Measurement protocol, Prototype, Reference machine for this run, Rejected alternatives and risks, Results, U4 capture-cost prototype gate

### Community 85 - "capture_soak.sh"
Cohesion: 0.31
Nodes (4): sample_footprint(), capture_soak.sh script, stop_helper(), usage()

### Community 86 - "VisionResult"
Cohesion: 0.29
Nodes (6): Option, Self, Vec, VisionFinding, VisionKind, VisionResult

### Community 87 - "mask_image"
Cohesion: 0.29
Nodes (12): dilated_rect(), mask_image(), PixelBounds, validate_rect(), assert_rect_is_masked(), coverage_proof_is_verifiable_against_detection_set_and_pixels(), detection(), edge_touching_detection_is_fully_covered_without_writing_outside_image() (+4 more)

### Community 88 - "RuntimeLimits"
Cohesion: 0.29
Nodes (5): CliRuntime, OutputLimit, RuntimeLimits, Timeout, NonZeroUsize

### Community 89 - "qaptr-store/src/schema.rs"
Cohesion: 0.44
Nodes (8): has_forbidden_name_part(), rejects_blob_columns(), rejects_image_like_tables(), Connection, Result, valid_connection(), validate(), validate_table()

### Community 90 - "MemoryCredentials"
Cohesion: 0.24
Nodes (10): MemoryCredentials, CaptureId, Result, CredentialKey, CredentialPort, CredentialValue, Mutex, OcrResult (+2 more)

### Community 91 - "U9 OCR and Vision measurement"
Cohesion: 0.25
Nodes (7): Human-labeled recall, Reference machine, Reproducible procedure, Results, Scope, U9 OCR and Vision measurement, Verification notes

### Community 92 - "U3 shell measurement gate"
Cohesion: 0.25
Nodes (7): Decision, Gate and scope, Identity and signing shape, Measurements, Screen Recording TCC persistence, U3 shell measurement gate, What would overturn the decision

### Community 93 - "FakeProvider"
Cohesion: 0.21
Nodes (9): FakeProvider, Option, ProviderError, Self, ProviderAdapter, ProviderDescriptor, ProviderDetection, ProviderInvocation (+1 more)

### Community 95 - "Website design rationale (U21)"
Cohesion: 0.25
Nodes (7): Accessibility and performance commitments, Layout, in order, Motion, Website design rationale (U21), What Qaptr deliberately does not copy, What Qaptr matches, What was observed on shopify.design

### Community 96 - "U22 packaging evidence"
Cohesion: 0.25
Nodes (7): Credential-blocked claims, Developer ID release procedure, Local verification without Apple credentials, Qaptr v1 release evidence, Rejected alternatives, U16 provider detection evidence, U22 packaging evidence

### Community 97 - "Result"
Cohesion: 0.29
Nodes (4): Result, Transaction, WriteTransaction, WriteTransaction<'transaction>

### Community 98 - "measure.py"
Cohesion: 0.48
Nodes (6): descendants(), footprint(), kill_tree(), main(), Path, run_once()

### Community 99 - "U12 full preparation measurement"
Cohesion: 0.33
Nodes (5): Interpretation and confidence, Reference machine, Reproducible procedure, Scope, U12 full preparation measurement

### Community 100 - "main.rs"
Cohesion: 0.47
Nodes (4): append_line(), record_paint(), String, screen_capture_permission()

### Community 101 - "MacVision"
Cohesion: 0.29
Nodes (7): MacVision, CaptureId, Into, PathBuf, PortResult, Result, Self

### Community 102 - "Product Contract"
Cohesion: 0.33
Nodes (6): Acceptance examples, Core interaction, Explicit non-goals for v1, Primary outcome, Product Contract, Requirements

### Community 104 - "migrations/mod.rs"
Cohesion: 0.50
Nodes (3): apply(), Connection, Result

### Community 105 - "Qaptr capture helper"
Cohesion: 0.50
Nodes (3): Build, Qaptr capture helper, Security and ownership invariants

### Community 107 - "MacOcr"
Cohesion: 0.31
Nodes (7): MacOcr, CaptureId, Into, PathBuf, PortResult, Result, Self

### Community 121 - "Decoder"
Cohesion: 0.22
Nodes (8): Cell, CaptureDecoder, CancelAfterPreparation, Decoder, String, HashMap, OpenedBundle, PreparationInput

### Community 124 - "Confidence"
Cohesion: 0.16
Nodes (9): OcrResult, Into, Option, Self, String, Vec, TextRegion, Confidence (+1 more)

### Community 125 - "Working in this repository"
Cohesion: 0.18
Nodes (8): Knowledge graph first, Parallel agents, Quality gates, Working in this repository, Codebase map, Development, Qaptr, Status

### Community 126 - "runtime"
Cohesion: 0.44
Nodes (10): environment_is_cleared_before_allowlisted_values_are_added(), executable(), metacharacters_are_passed_as_literal_arguments_without_shell_interpretation(), nonexistent_binary_maps_to_not_installed(), oversized_output_is_refused_without_retaining_unbounded_bytes(), prompt_is_sent_over_stdin_without_becoming_an_argument(), CliRuntime, runtime() (+2 more)

### Community 127 - "PermissionState"
Cohesion: 0.31
Nodes (3): PermissionPort, PermissionState, InMemoryPermissions

### Community 128 - "NormalizedRect"
Cohesion: 0.22
Nodes (3): NormalizedRect, Result, Self

### Community 129 - "RecognitionResult"
Cohesion: 0.29
Nodes (6): RecognitionResult, recognize(), CaptureId, O, Result, V

### Community 130 - "Harness"
Cohesion: 0.22
Nodes (9): FakeOcr, FakeVision, Harness, PrivacyGate, Store, Vault, FixedClock, OcrPort (+1 more)

### Community 131 - "0001_initial.sql"
Cohesion: 0.67
Nodes (3): captures, observations, workflows

### Community 134 - "ProviderDetection"
Cohesion: 0.39
Nodes (3): AuthenticationStatus, ProviderDetection, Option

### Community 135 - "Error"
Cohesion: 0.38
Nodes (4): DomainError, String, WorkflowError, Error

### Community 137 - "TempRoot"
Cohesion: 0.33
Nodes (4): TempRoot, Drop, Path, PathBuf

### Community 138 - ".into_result"
Cohesion: 0.50
Nodes (3): Response<T>, Result, T

## Knowledge Gaps
- **218 isolated node(s):** `Knowledge graph first`, `Parallel agents`, `Quality gates`, `Status`, `Development` (+213 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **27 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Duration` connect `Duration` to `DetailedCaptureProfile`, `MacVision`, `enforce_retention`, `MacOcr`, `RuntimeLimits`, `.prepare`, `MacosError`, `CliRuntimeError`, `runtime`?**
  _High betweenness centrality (0.080) - this node is a cross-community bridge._
- **Why does `CliRuntimeError` connect `CliRuntimeError` to `FakeExecutor`, `CliOutput`, `ProviderError`, `.new`, `CliInvocation`, `.run`, `.new`?**
  _High betweenness centrality (0.064) - this node is a cross-community bridge._
- **Why does `Confidence` connect `Confidence` to `Self`, `Duration`, `RawProviderResponse`, `ObservationRecord`, `VisionResult`, `MacosError`?**
  _High betweenness centrality (0.050) - this node is a cross-community bridge._
- **What connects `Knowledge graph first`, `Parallel agents`, `Quality gates` to the rest of the system?**
  _218 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Self` be split into smaller, more focused modules?**
  _Cohesion score 0.054690204222914506 - nodes in this community are weakly interconnected._
- **Should `classes.rs` be split into smaller, more focused modules?**
  _Cohesion score 0.06915113871635611 - nodes in this community are weakly interconnected._
- **Should `src/analyze.rs` be split into smaller, more focused modules?**
  _Cohesion score 0.056051587301587304 - nodes in this community are weakly interconnected._