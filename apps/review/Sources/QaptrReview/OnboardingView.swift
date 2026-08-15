import QaptrReviewCore
import SwiftUI

/// Truthful, non-nagging onboarding across five stages (R-D7, AE9).
///
/// Runs once per installation (`SettingsPreferences.onboardingCompleted`) and
/// never requests a provider before the final privacy-consent stage.
struct OnboardingView: View {
    @Bindable var model: ReviewAppModel
    @State private var stage: OnboardingStage = .permissions
    /// Direction of the most recent stage change, used to make forward and
    /// backward transitions read as genuinely directional (content slides
    /// from the trailing edge going forward, from the leading edge going
    /// back) instead of the same motion regardless of which way the user
    /// moved.
    @State private var direction: StageDirection = .forward
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                progressIndicator
                Spacer()
                // A quiet step numeral in the report mono voice, sitting on
                // the same row as the progress hairlines rather than
                // floating behind body copy. An earlier version anchored a
                // much larger numeral to the top-trailing corner of the
                // whole view in a ZStack, which visually collided with
                // wrapped body text in stages with more copy (the numeral
                // sat behind, not beside, the content). Keeping it inline
                // and modestly sized avoids any overlap while still giving
                // each stage its own quiet position marker beyond the thin
                // progress hairlines.
                //
                // The row uses `.center` alignment, not `.top`: the
                // progress capsules are only 2-3pt tall while this label's
                // font has a much taller line box, so top-aligning left the
                // label hanging visibly below the capsules' vertical
                // center instead of sharing one baseline-adjacent center
                // line with them.
                Text("0\(stage.rawValue + 1) / 0\(OnboardingStage.allCases.count)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.bottom, 28)

            if reduceMotion {
                stageHeader
                content
                    .padding(.top, 20)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    stageHeader
                    content
                }
                .id(stage)
                .transition(stageTransition)
            }

            Spacer(minLength: 32)

            HStack {
                if let previous = stage.previous {
                    QuietButton(title: "Back") {
                        go(to: previous, direction: .backward)
                    }
                }
                Spacer()
                PrimaryActionButton(title: stage == .privacyConsent ? "Finish" : "Continue") {
                    advance()
                }
                .disabled(stage == .privacyConsent && model.loadError != nil)
            }
        }
        .padding(40)
        .frame(maxWidth: 600, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.qaptrSurface)
    }

    private enum StageDirection {
        case forward
        case backward
    }

    private var stageTransition: AnyTransition {
        switch direction {
        case .forward:
            .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .move(edge: .leading))
            )
        case .backward:
            .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .leading)),
                removal: .opacity.combined(with: .move(edge: .trailing))
            )
        }
    }

    /// The stage title in the system serif design (New York), matching the
    /// website's editorial serif "voice" so the heading has real
    /// typographic presence instead of a flat system-sans label. The mono
    /// step numeral behind it stays the "report" counterpart, matching the
    /// two-voice contrast documented in docs/design/website.md.
    ///
    /// `Font.custom("New York", ...)` silently falls back to the system
    /// sans face because "New York" is not the font's actual PostScript
    /// name; the documented way to reach it from SwiftUI is
    /// `Font.system(design: .serif)`, which resolves to New York on macOS.
    private var stageHeader: some View {
        Text(stage.title)
            .font(.system(size: 34, weight: .semibold, design: .serif))
    }

    /// Five thin hairline segments showing onboarding position. The current
    /// stage is rendered in the single amber accent, earning its one use in
    /// this surface for the one moment that represents real forward
    /// momentum; passed stages read `.primary`, future stages fade to a very
    /// low opacity. No new state: position and fill are derived directly
    /// from `OnboardingStage.allCases` and the current `stage`'s `rawValue`.
    ///
    /// The individual capsules are decorative only (`.accessibilityHidden`);
    /// VoiceOver instead reads the whole indicator as a single "Step N of 5"
    /// element, since five unlabeled shapes would otherwise announce as
    /// meaningless geometry with no equivalent of the visual position cue.
    private var progressIndicator: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStage.allCases, id: \.self) { candidate in
                Capsule()
                    .fill(fill(for: candidate))
                    .frame(height: candidate == stage ? 3 : 2)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: stage)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(stage.rawValue + 1) of \(OnboardingStage.allCases.count)")
    }

    private func fill(for candidate: OnboardingStage) -> AnyShapeStyle {
        if candidate == stage {
            AnyShapeStyle(Color(nsColor: .systemOrange))
        } else if candidate.rawValue < stage.rawValue {
            AnyShapeStyle(Color.primary.opacity(0.8))
        } else {
            AnyShapeStyle(Color.primary.opacity(0.12))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .permissions:
            permissionsStage
        case .displays:
            displaysStage
        case .captureExplanation:
            captureExplanationStage
        case .providerSelection:
            providerSelectionStage
        case .privacyConsent:
            privacyConsentStage
        }
    }

    private var permissionsStage: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Let Qaptr take small screenshots now and then. It does not record all the time.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(model.settings.screenRecordingStatus.label)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if model.settings.screenRecordingStatus != .granted {
                        ActionButton(title: "Allow screenshots", action: model.requestScreenRecording)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Optional: let Qaptr read the app and window name. You can skip this.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(model.settings.accessibilityContextStatus.label)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if model.settings.accessibilityContextStatus != .granted {
                        ActionButton(title: "Allow app names", action: model.requestAccessibilityContext)
                    }
                }
            }
        }
    }

    private var displaysStage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Qaptr uses every screen you have. You can pick fewer screens later.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("\(model.settings.availableDisplayIDs.count) screens found")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private var captureExplanationStage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Qaptr takes one small screenshot every \(CaptureIntervalPolicy.humanized(model.settings.intervalSeconds)). It notes the app and window name you use.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("It does not record all the time. It does not read your clipboard or keys.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private var providerSelectionStage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick the AI tool that writes your notes. You can change this later.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            ProviderChoiceList(selection: providerBinding)
        }
    }

    private var privacyConsentStage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Qaptr hides text, faces, and barcodes on your Mac before a review is shared.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("Nothing is sent until you say yes.")
                .font(.system(size: 14, weight: .medium))
            if model.loadError != nil {
                Text("Secure capture setup could not be completed. Quit and reopen Qaptr before finishing onboarding.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }
        }
    }

    private var providerBinding: Binding<ProviderChoice?> {
        Binding(
            get: { model.settings.provider },
            set: { newValue in
                if let newValue {
                    model.setProvider(newValue)
                } else {
                    model.clearProvider()
                }
            }
        )
    }

    private func advance() {
        if let next = stage.next {
            go(to: next, direction: .forward)
        } else {
            guard model.loadError == nil else { return }
            model.completeOnboarding()
        }
    }

    private func go(to next: OnboardingStage, direction newDirection: StageDirection) {
        direction = newDirection
        if reduceMotion {
            stage = next
        } else {
            withAnimation(.easeOut(duration: 0.22)) {
                stage = next
            }
        }
    }
}

/// A plain typographic row list replacing the bare system `Picker` for
/// provider selection. The native menu-style picker renders as a small gray
/// AppKit control that reads as a stray system widget dropped into an
/// otherwise fully typographic layout; this list uses only text weight and
/// the single amber accent to show selection, no chrome, no card background,
/// matching the rest of the app's plain-shape-on-background language.
private struct ProviderChoiceList: View {
    @Binding var selection: ProviderChoice?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ProviderChoice.allCases, id: \.self) { provider in
                ProviderRow(provider: provider, isSelected: provider == selection) {
                    selection = provider
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// One selectable provider row. Selection was previously an instant
/// attribute snap (radio fill and text weight changed with no transition
/// at all) with no feedback on hover or press, the one interactive list in
/// the app that felt inert. This adds: a hover-tinted background wash, a
/// spring-eased radio-dot scale-in on selection, an animated fill-color
/// change instead of an instant snap, and the same tactile press-scale
/// used elsewhere in the app, so choosing a provider reads as a real,
/// felt action rather than a silent state mutation.
private struct ProviderRow: View {
    let provider: ProviderChoice
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color(nsColor: .systemOrange) : Color.primary.opacity(0.25),
                            lineWidth: 1.5
                        )
                        .frame(width: 14, height: 14)
                    Circle()
                        .fill(Color(nsColor: .systemOrange))
                        .frame(width: 8, height: 8)
                        .scaleEffect(isSelected ? 1 : 0.001)
                        .opacity(isSelected ? 1 : 0)
                }
                .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.6), value: isSelected)

                Text(provider.displayName)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isSelected)

                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovering ? 0.05 : 0))
            )
        }
        .buttonStyle(.tactile)
        .onHover { hovering in
            if reduceMotion {
                isHovering = hovering
            } else {
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
        }
    }
}
