import SwiftUI

struct FindingDetailView: View {
  @Bindable var model: AppModel
  let state: AppScreen

  @State private var correction = ""
  @FocusState private var correctionFocused: Bool

  private let ink = Color(red: 0.07, green: 0.09, blue: 0.15)
  private let bodyInk = Color(red: 0.29, green: 0.33, blue: 0.39)
  private let mutedInk = Color(red: 0.39, green: 0.45, blue: 0.55)
  private let blue = Color(red: 0.15, green: 0.39, blue: 0.92)
  private let green = Color(red: 0.10, green: 0.50, blue: 0.30)

  var body: some View {
    VStack(spacing: 0) {
      titleBar
      toolbar
      content
      Spacer(minLength: 0)
    }
    .frame(width: 845, height: 737)
    .background(Color.clear)
  }

  private var titleBar: some View {
    HStack(spacing: 8) {
      Image(systemName: "circle.hexagongrid.fill")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(QaptrColor.accent)
      Text("Qaptr Home")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Color.black.opacity(0.85))
      Spacer(minLength: 0)
    }
    .padding(.leading, 84)
    .padding(.trailing, 8)
    .frame(height: 32)
    .background(Color.white.opacity(0.60))
    .overlay(alignment: .bottom) { Divider().opacity(0.35) }
  }

  private var toolbar: some View {
    HStack {
      Button("← All findings") {
        model.screen = .homeFindings
      }
      .buttonStyle(.plain)
      .font(.system(size: 14, weight: .medium))
      .foregroundStyle(bodyInk)
      .accessibilityHint("Returns to the findings list")

      Spacer(minLength: 0)

      Button(state == .findingSaved ? "Saved ✓" : "Save workflow") {
        saveWorkflow()
      }
      .buttonStyle(FindingToolbarButtonStyle(saved: state == .findingSaved))
      .disabled(state == .findingSaved)
    }
    .padding(.horizontal, 40)
    .frame(height: 60)
    .background(Color.black.opacity(0.03))
    .overlay(alignment: .bottom) { Divider().opacity(0.22) }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Workflow")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(mutedInk)

      Text(isIncomplete ? "Compare launch plans and record the decision" : "Validate a product change before release")
        .font(.system(size: 26, weight: .regular))
        .foregroundStyle(ink)
        .lineSpacing(6)
        .fixedSize(horizontal: false, vertical: true)

      Text(summary)
        .font(.system(size: 15))
        .foregroundStyle(bodyInk)
        .lineSpacing(7)
        .frame(maxWidth: 600, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 8) {
        captureChip
        if state == .findingSaved {
          savedChip
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
      }

      if isIncomplete {
        incompleteCard
      } else if state == .findingCorrection {
        correctionForm
      } else {
        Color.clear.frame(height: 8)
        correctionLink
      }
    }
    .padding(.top, 18)
    .padding(.horizontal, 40)
    .padding(.bottom, 40)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var summary: String {
    if isIncomplete {
      return "A product brief and planning document appeared together while tradeoffs were reviewed. The captures show the comparison, but not the final decision."
    }
    return "Qaptr repeatedly saw implementation, review feedback, and a packaged-build check in the same work period. The sequence repeated three times with the same tools in the same order."
  }

  private var isIncomplete: Bool { state == .findingIncomplete }

  private var captureChip: some View {
    Text(isIncomplete ? "📷 4 captures · 26 min · 10:04 – 10:30 AM" : "📷 8 captures · 42 min · 9:48 – 10:30 AM")
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(bodyInk)
      .padding(.horizontal, 12)
      .frame(height: 28)
      .background(Color.black.opacity(0.04), in: Capsule())
  }

  private var savedChip: some View {
    Text("Saved to workflows")
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(green)
      .padding(.horizontal, 12)
      .frame(height: 28)
      .background(green.opacity(0.12), in: Capsule())
  }

  private var incompleteCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Qaptr can watch more closely for 30 minutes to finish the picture. It returns to the normal rhythm on its own.")
        .font(.system(size: 15))
        .foregroundStyle(bodyInk)
        .lineSpacing(7)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 20) {
        Button("Capture more detail") {
          model.screen = .homeWatching
          model.toast = "Watching more closely for 30 minutes"
        }
        .buttonStyle(FindingPrimaryButtonStyle())

        Button("Keep it as is") {
          model.screen = .findingComplete
          model.toast = "Finding kept as is"
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(bodyInk)
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .qaptrGlassSurface(radius: 24)
    .shadow(color: .black.opacity(0.06), radius: 32, y: 12)
    .padding(.top, 1)
  }

  private var correctionLink: some View {
    Button("Something off? Tell Qaptr →") {
      model.screen = .findingCorrection
    }
    .buttonStyle(.plain)
    .font(.system(size: 12, weight: .bold))
    .foregroundStyle(blue)
  }

  private var correctionForm: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("What did Qaptr get wrong?")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(mutedInk)

      ZStack(alignment: .topLeading) {
        TextEditor(text: $correction)
          .font(.system(size: 15))
          .foregroundStyle(bodyInk)
          .scrollContentBackground(.hidden)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .focused($correctionFocused)

        if correction.isEmpty {
          Text("Tell Qaptr what to correct…")
            .font(.system(size: 15))
            .foregroundStyle(mutedInk.opacity(0.70))
            .padding(.leading, 14)
            .padding(.top, 12)
            .allowsHitTesting(false)
        }
      }
      .frame(height: 88)
      .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
      .overlay {
        RoundedRectangle(cornerRadius: 10)
          .strokeBorder(Color.black.opacity(correctionFocused ? 0.16 : 0.08), lineWidth: 0.5)
      }

      HStack(spacing: 16) {
        Button("Save correction") {
          correctionFocused = false
          model.toast = "Correction saved on this Mac"
          model.screen = .findingComplete
        }
        .buttonStyle(FindingCorrectionButtonStyle(enabled: !trimmedCorrection.isEmpty))
        .disabled(trimmedCorrection.isEmpty)

        Text("Saved on this Mac. The current explanation stays until Qaptr revises it.")
          .font(.system(size: 12))
          .foregroundStyle(mutedInk)
          .lineSpacing(4)
      }
    }
    .padding(.top, 8)
  }

  private var trimmedCorrection: String {
    correction.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func saveWorkflow() {
    guard state != .findingSaved else { return }
    model.screen = .findingSaved
    model.toast = "Workflow saved"
  }
}

private struct FindingToolbarButtonStyle: ButtonStyle {
  let saved: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13))
      .foregroundStyle(saved ? Color(red: 0.10, green: 0.50, blue: 0.30) : Color(red: 0, green: 0.53, blue: 1))
      .padding(.horizontal, 16)
      .frame(height: 24)
      .background((saved ? Color.green : Color.blue).opacity(configuration.isPressed ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 6))
  }
}

private struct FindingPrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13))
      .foregroundStyle(.white)
      .frame(width: 157, height: 32)
      .background(Color(red: 0.15, green: 0.39, blue: 0.92), in: RoundedRectangle(cornerRadius: 12))
      .shadow(color: Color(red: 0.15, green: 0.39, blue: 0.92).opacity(0.20), radius: 12, y: 4)
      .opacity(configuration.isPressed ? 0.82 : 1)
  }
}

private struct FindingCorrectionButtonStyle: ButtonStyle {
  let enabled: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13))
      .foregroundStyle(enabled ? Color.white : Color(red: 0.07, green: 0.09, blue: 0.15).opacity(0.45))
      .padding(.horizontal, 16)
      .frame(height: 32)
      .background(enabled ? QaptrColor.accent : Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
      .opacity(configuration.isPressed ? 0.82 : 1)
  }
}
