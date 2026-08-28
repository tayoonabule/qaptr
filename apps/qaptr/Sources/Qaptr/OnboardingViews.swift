import SwiftUI

struct OnboardingView: View {
  @Bindable var model: AppModel
  let state: AppScreen

  var body: some View {
    ZStack {
      QaptrCanvas()

      VStack(spacing: 0) {
        QTitleBar("Qaptr Setup")

        VStack(spacing: 72) {
          header
          permissionSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(60)
      }
    }
    .frame(width: 845, height: 737)
    .clipped()
  }

  private var header: some View {
    VStack(spacing: 32) {
      QaptrBrand()
        .frame(width: 140, height: 50.7)

      Text(copy.title)
        .font(.system(size: 26, weight: .regular))
        .foregroundStyle(.black)
        .multilineTextAlignment(.center)
        .lineSpacing(1)
        .frame(width: 416)
    }
  }

  private var permissionSection: some View {
    VStack(spacing: 16) {
      QGlassCard {
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
              Text("Allow Screen Recording")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255))
                .frame(height: 20)

              if let badge = copy.badge {
                PermissionBadge(text: badge.text, color: badge.color)
              }
            }

            Text(copy.detail)
              .font(.system(size: 13, weight: .regular))
              .foregroundStyle(Color(red: 68 / 255, green: 68 / 255, blue: 68 / 255))
              .lineSpacing(0)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          Button(action: advance) {
            HStack(spacing: 8) {
              Text(copy.buttonTitle)
              Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14.4, height: 14.4)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(QGlassButtonStyle())
          .accessibilityHint(copy.buttonHint)
        }
        .frame(width: 532)
      }
      .frame(width: 580)

      HStack(spacing: 8) {
        Image(systemName: "checkmark.shield")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Color(red: 102 / 255, green: 102 / 255, blue: 102 / 255))
          .frame(width: 22, height: 22)
          .overlay {
            Circle()
              .strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5)
          }

        Text(copy.footer)
          .font(.system(size: 12, weight: .regular))
          .foregroundStyle(Color(red: 102 / 255, green: 102 / 255, blue: 102 / 255))
          .frame(height: 15)
      }
    }
  }

  private func advance() {
    switch state {
    case .setupPermission:
      model.screen = .setupWaiting
    case .setupWaiting:
      model.screen = .setupDenied
    case .setupDenied:
      model.screen = .homeEmpty
    default:
      model.screen = .homeEmpty
    }
  }

  private var copy: Copy {
    switch state {
    case .setupWaiting:
      Copy(
        title: "You’re so close!!!",
        badge: Badge(text: "Waiting...", color: Color(red: 1, green: 141 / 255, blue: 40 / 255)),
        detail: "Screen Recording is the one required permission. QaptrHelper owns capture and reports the live result here.",
        buttonTitle: "Allow Screen Recording",
        buttonHint: "Continues to the denied permission example.",
        footer: "You can change privacy and capture choices later in Settings."
      )
    case .setupDenied:
      Copy(
        title: "Uh oh. Our local tools can’t Qaptr much without seeing your screen.",
        badge: Badge(text: "Denied", color: Color(red: 1, green: 56 / 255, blue: 60 / 255)),
        detail: "Screen Recording is the one required permission. QaptrHelper owns capture and reports the live result here.",
        buttonTitle: "Open System Settings",
        buttonHint: "Continues to Qaptr home.",
        footer: "Enable QaptrHelper in Screen Recording, then return to Qaptr."
      )
    default:
      Copy(
        title: "Finally, a way to Qaptr that one task you’ve always wanted to delegate.",
        badge: nil,
        detail: "Screen Recording is the one required permission.",
        buttonTitle: "Grant Permission in Settings",
        buttonHint: "Continues to the waiting permission state.",
        footer: "Captures stay 100% offline. You can pause or adjust permission settings anytime."
      )
    }
  }
}

private extension OnboardingView {
  struct Copy {
    let title: String
    let badge: Badge?
    let detail: String
    let buttonTitle: String
    let buttonHint: String
    let footer: String
  }

  struct Badge {
    let text: String
    let color: Color
  }
}

private struct PermissionBadge: View {
  let text: String
  let color: Color

  var body: some View {
    Text(text)
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(color)
      .frame(height: 13)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(color.opacity(0.102), in: Capsule())
      .accessibilityLabel("Permission status: \(text)")
  }
}
