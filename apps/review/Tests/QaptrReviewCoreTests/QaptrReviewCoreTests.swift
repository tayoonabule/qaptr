import Foundation
import XCTest
@testable import QaptrReviewCore

final class ConfidenceBandTests: XCTestCase {
    func testLowBandForScoresUnderHalf() {
        XCTAssertEqual(ConfidenceBand(score: 0.0), .low)
        XCTAssertEqual(ConfidenceBand(score: 0.49), .low)
    }

    func testModerateBandForScoresInRange() {
        XCTAssertEqual(ConfidenceBand(score: 0.5), .moderate)
        XCTAssertEqual(ConfidenceBand(score: 0.79), .moderate)
    }

    func testHighBandForScoresAtOrAboveEightyPercent() {
        XCTAssertEqual(ConfidenceBand(score: 0.8), .high)
        XCTAssertEqual(ConfidenceBand(score: 1.0), .high)
    }

    func testNeverInventsCertaintyForAZeroScore() {
        XCTAssertEqual(ConfidenceBand(score: 0.0).label, "Low confidence")
    }
}

final class ReviewSnapshotDecoderTests: XCTestCase {
    func testDecodesFullSnapshot() throws {
        let json = """
        {
          "observations": [
            {
              "id": "observation-1",
              "capture_id": "capture-1",
              "session_id": "session-1",
              "title": "Reviewed a shared doc",
              "summary": "You reviewed a shared document for ten minutes.",
              "confidence": 0.72,
              "created_at_ms": 2000
            }
          ],
          "workflows": [
            {
              "id": "workflow-1",
              "session_id": "session-1",
              "title": "Weekly report review",
              "goal": "Check the weekly numbers",
              "context": "Spreadsheet review",
              "tools": "Sheets",
              "sequence": "Open, scan, comment",
              "decisions": "None",
              "variations": "None",
              "evidence_confidence": 0.6,
              "created_at_ms": 3000
            }
          ],
          "notices": [
            {
              "id": "notice-1",
              "created_at_ms": 1000,
              "count": 2,
              "text": "2 captures were excluded because they could not be safely prepared."
            }
          ]
        }
        """
        let snapshot = try ReviewSnapshotDecoder.decode(Data(json.utf8))
        XCTAssertEqual(snapshot.observations.count, 1)
        XCTAssertEqual(snapshot.observations[0].title, "Reviewed a shared doc")
        XCTAssertEqual(snapshot.observations[0].confidenceBand, .moderate)
        XCTAssertEqual(snapshot.workflows.count, 1)
        XCTAssertEqual(snapshot.workflows[0].title, "Weekly report review")
        XCTAssertEqual(snapshot.notices.count, 1)
        XCTAssertEqual(snapshot.notices[0].count, 2)
    }

    func testDecodesEmptySnapshot() throws {
        let json = "{\"observations\": [], \"workflows\": [], \"notices\": []}"
        let snapshot = try ReviewSnapshotDecoder.decode(Data(json.utf8))
        XCTAssertEqual(snapshot, .empty)
    }

    func testRejectsNonObjectRoot() {
        XCTAssertThrowsError(try ReviewSnapshotDecoder.decode(Data("[]".utf8))) { error in
            XCTAssertEqual(error as? ReviewSnapshotDecodeError, .unexpectedShape("root is not an object"))
        }
    }

    func testRejectsMissingRequiredField() {
        let json = "{\"observations\": [{\"id\": \"x\"}], \"workflows\": [], \"notices\": []}"
        XCTAssertThrowsError(try ReviewSnapshotDecoder.decode(Data(json.utf8)))
    }
}

final class ReviewStatusDecoderTests: XCTestCase {
    func testDecodesAReadyStatusWithHistoryAvailable() throws {
        let json = """
        {
          "store": { "ready": true },
          "review_session": {
            "state": "ready",
            "history_available": true,
            "observation_count": 1,
            "workflow_count": 0,
            "notice_count": 0
          },
          "analysis": {
            "state": "unavailable",
            "provider": null,
            "reason": "live provider analysis is not exposed by qaptr-review-ffi"
          }
        }
        """
        let status = try ReviewStatusDecoder.decode(Data(json.utf8))
        XCTAssertEqual(status.store.ready, true)
        XCTAssertEqual(status.reviewSession.state, "ready")
        XCTAssertEqual(status.reviewSession.historyAvailable, true)
        XCTAssertEqual(status.reviewSession.observationCount, 1)
        XCTAssertEqual(status.reviewSession.workflowCount, 0)
        XCTAssertEqual(status.reviewSession.noticeCount, 0)
        XCTAssertEqual(status.analysis.state, "unavailable")
        XCTAssertNil(status.analysis.provider)
        XCTAssertEqual(
            status.analysis.reason,
            "live provider analysis is not exposed by qaptr-review-ffi"
        )
    }

    func testDecodesHistoryUnavailableWhenNothingHasBeenRecorded() throws {
        let json = """
        {
          "store": { "ready": true },
          "review_session": {
            "state": "ready",
            "history_available": false,
            "observation_count": 0,
            "workflow_count": 0,
            "notice_count": 0
          },
          "analysis": { "state": "unavailable", "provider": null, "reason": "no analysis" }
        }
        """
        let status = try ReviewStatusDecoder.decode(Data(json.utf8))
        XCTAssertEqual(status.reviewSession.historyAvailable, false)
    }

    func testRejectsNonObjectRoot() {
        XCTAssertThrowsError(try ReviewStatusDecoder.decode(Data("[]".utf8))) { error in
            XCTAssertEqual(error as? ReviewSnapshotDecodeError, .unexpectedShape("root is not an object"))
        }
    }

    func testRejectsMissingReviewSessionObject() {
        let json = """
        { "store": { "ready": true }, "analysis": { "state": "unavailable" } }
        """
        XCTAssertThrowsError(try ReviewStatusDecoder.decode(Data(json.utf8))) { error in
            XCTAssertEqual(
                error as? ReviewSnapshotDecodeError,
                .unexpectedShape("status missing a \"review_session\" object")
            )
        }
    }

    func testRejectsReviewSessionMissingARequiredField() {
        let json = """
        {
          "store": { "ready": true },
          "review_session": { "state": "ready", "history_available": true, "observation_count": 0 },
          "analysis": { "state": "unavailable" }
        }
        """
        XCTAssertThrowsError(try ReviewStatusDecoder.decode(Data(json.utf8)))
    }
}

final class ReviewSnapshotOrderingTests: XCTestCase {
    func testOrdersObservationsMostRecentFirst() {
        let older = QaptrObservation(
            id: "a", captureID: nil, sessionID: "s", title: "Older", summary: "",
            confidence: 0.5, createdAtMillis: 100
        )
        let newer = QaptrObservation(
            id: "b", captureID: nil, sessionID: "s", title: "Newer", summary: "",
            confidence: 0.5, createdAtMillis: 200
        )
        let snapshot = ReviewSnapshot(observations: [older, newer], workflows: [], notices: [])
        XCTAssertEqual(snapshot.recentObservations.map(\.id), ["b", "a"])
    }
}

final class SettingsPreferencesTests: XCTestCase {
    func testDefaultsToOneDayCacheLifetime() {
        let preferences = SettingsPreferences(store: InMemoryPreferenceStore())
        XCTAssertEqual(preferences.cacheLifetime, .oneDay)
    }

    func testPersistsAChosenCacheLifetime() {
        let preferences = SettingsPreferences(store: InMemoryPreferenceStore())
        preferences.cacheLifetime = .sevenDays
        XCTAssertEqual(preferences.cacheLifetime, .sevenDays)
    }

    func testPersistsAChosenProvider() {
        let preferences = SettingsPreferences(store: InMemoryPreferenceStore())
        XCTAssertNil(preferences.provider)
        preferences.provider = .claudeCLI
        XCTAssertEqual(preferences.provider, .claudeCLI)
    }

    func testClearsAChosenProvider() {
        let preferences = SettingsPreferences(store: InMemoryPreferenceStore())
        preferences.provider = .claudeCLI
        preferences.provider = nil
        XCTAssertNil(preferences.provider)
    }

    func testPersistsAnExplicitModelOverrideSeparatelyFromProvider() {
        let preferences = SettingsPreferences(store: InMemoryPreferenceStore())
        preferences.provider = .openRouter
        preferences.explicitModelOverride = "  openai/gpt-5  "

        XCTAssertEqual(preferences.provider, .openRouter)
        XCTAssertEqual(preferences.explicitModelOverride, "openai/gpt-5")
    }

    func testRejectsAnEmptyExplicitModelOverride() {
        let preferences = SettingsPreferences(store: InMemoryPreferenceStore())
        preferences.explicitModelOverride = "   "
        XCTAssertNil(preferences.explicitModelOverride)
    }

    func testAddsNormalizedExcludedApplicationAndRejectsBlankEntries() {
        let preferences = SettingsPreferences(store: InMemoryPreferenceStore())
        preferences.addExcludedApplication("  1Password  ")
        preferences.addExcludedApplication("   ")
        XCTAssertEqual(preferences.excludedApplications, ["1Password"])
    }

    func testDoesNotDuplicateAnAlreadyExcludedApplication() {
        let preferences = SettingsPreferences(store: InMemoryPreferenceStore())
        preferences.addExcludedApplication("Messages")
        preferences.addExcludedApplication("Messages")
        XCTAssertEqual(preferences.excludedApplications, ["Messages"])
    }

    func testRemovesAnExcludedWindowTitle() {
        let preferences = SettingsPreferences(store: InMemoryPreferenceStore())
        preferences.addExcludedWindowTitle("Private Browsing")
        preferences.removeExcludedWindowTitle("Private Browsing")
        XCTAssertTrue(preferences.excludedWindowTitles.isEmpty)
    }

    func testOnboardingIsNotCompletedByDefault() {
        let preferences = SettingsPreferences(store: InMemoryPreferenceStore())
        XCTAssertFalse(preferences.onboardingCompleted)
        preferences.onboardingCompleted = true
        XCTAssertTrue(preferences.onboardingCompleted)
    }
}

final class ProviderChoiceTests: XCTestCase {
    func testExposesExactlyTheFourSupportedProviderIdentifiers() {
        XCTAssertEqual(
            ProviderChoice.allCases.map(\.displayName),
            ["OpenRouter", "Claude CLI", "Codex CLI", "Jcode CLI"]
        )
    }
}

final class OnboardingStageTests: XCTestCase {
    func testAdvancesThroughAllFiveStagesInOrder() {
        var stage: OnboardingStage? = .permissions
        var seen: [OnboardingStage] = []
        while let current = stage {
            seen.append(current)
            stage = current.next
        }
        XCTAssertEqual(
            seen,
            [.permissions, .displays, .captureExplanation, .providerSelection, .privacyConsent]
        )
    }

    func testPrivacyConsentIsTheTerminalStage() {
        XCTAssertNil(OnboardingStage.privacyConsent.next)
    }
}

final class PermissionStatusTests: XCTestCase {
    func testMapsBridgeCodesToTheCorrectStatus() {
        XCTAssertEqual(PermissionStatus(bridgeCode: 1), .granted)
        XCTAssertEqual(PermissionStatus(bridgeCode: 0), .denied)
        XCTAssertEqual(PermissionStatus(bridgeCode: -1), .notDetermined)
        XCTAssertEqual(PermissionStatus(bridgeCode: -2), .unavailable)
        XCTAssertEqual(PermissionStatus(bridgeCode: 99), .unavailable)
    }
}

final class ReviewFFILibraryPathTests: XCTestCase {
    func testPrefersExplicitDevelopmentPathAndKeepsAdjacentExecutableFallback() {
        let candidates = ReviewFFILibraryPath.candidates(
            environment: [
                "QAPTR_REVIEW_FFI_LIBRARY_PATH": "/tmp/explicit/libqaptr_review_ffi.dylib",
                "QAPTR_REVIEW_FFI_LIBRARY_DIR": "/tmp/development"
            ],
            bundle: .main
        )

        XCTAssertEqual(candidates.first, "/tmp/explicit/libqaptr_review_ffi.dylib")
        XCTAssertTrue(candidates.contains("/tmp/development/libqaptr_review_ffi.dylib"))
        XCTAssertEqual(candidates.filter { $0 == "/tmp/explicit/libqaptr_review_ffi.dylib" }.count, 1)
    }

    func testSecureBootstrapUsesTheVaultBesideDurableHistory() {
        let store = URL(fileURLWithPath: "/Users/example/Library/Application Support/Qaptr/history.sqlite3")
        XCTAssertEqual(
            ReviewBridge.defaultVaultPath(for: store).path,
            "/Users/example/Library/Application Support/Qaptr/vault"
        )
    }
}

final class CacheLifetimeTests: XCTestCase {
    func testOrdersLifetimesFromShortestToLongestInSeconds() {
        let seconds = CacheLifetime.allCases.map(\.seconds)
        XCTAssertEqual(seconds, seconds.sorted())
    }
}

/// Onboarding copy is pure and driven only by already-known local state
/// (R-D7, KTD10). These tests assert the truthful statements checklist 5.1
/// requires: periodic capture from the live interval, local privacy
/// preparation, and just-in-time consent that is never granted once and
/// forgotten.
final class OnboardingCopyTests: XCTestCase {
    func testPeriodicCaptureStatementReflectsTheLiveConfiguredInterval() {
        XCTAssertEqual(
            OnboardingCopy.periodicCaptureStatement(intervalSeconds: 60),
            "Qaptr takes one screenshot every 1 minute."
        )
        XCTAssertEqual(
            OnboardingCopy.periodicCaptureStatement(intervalSeconds: 5),
            "Qaptr takes one screenshot every 5 seconds."
        )
    }

    func testCaptureBoundaryStatementNamesNoProhibitedVocabulary() {
        let statement = OnboardingCopy.captureBoundaryStatement.lowercased()
        for banned in ["pause", "sparse", "frequency"] {
            XCTAssertFalse(statement.contains(banned), "capture boundary copy must not use '\(banned)'")
        }
    }

    func testLocalPreparationStatementNamesThisDeviceBeforeAnyProvider() {
        XCTAssertTrue(OnboardingCopy.localPreparationStatement.contains("this Mac"))
        XCTAssertTrue(OnboardingCopy.localPreparationStatement.contains("before"))
    }

    func testJustInTimeConsentStatementDisclaimsThatChoosingAProviderSendsNothing() {
        XCTAssertTrue(OnboardingCopy.justInTimeConsentStatement.contains("does not send anything yet"))
    }

    func testProviderTransmissionStatementIsProviderAgnosticWhenNoneChosen() {
        let statement = OnboardingCopy.providerTransmissionStatement(provider: nil)
        for provider in ProviderChoice.allCases {
            XCTAssertFalse(statement.contains(provider.displayName))
        }
        XCTAssertTrue(statement.contains("will not send anything"))
    }

    func testProviderTransmissionStatementNamesTheChosenProviderOnlyOnceSelected() {
        let statement = OnboardingCopy.providerTransmissionStatement(provider: .openRouter)
        XCTAssertTrue(statement.contains("OpenRouter"))
        XCTAssertTrue(statement.contains("after you separately consent"))
    }
}
