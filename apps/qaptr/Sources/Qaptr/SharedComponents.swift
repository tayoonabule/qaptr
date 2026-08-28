import SwiftUI

struct QaptrTitleBar<Trailing: View>: View {
  let title: String
  let subtitle: String?
  @ViewBuilder let trailing: Trailing

  init(
    _ title: String,
    subtitle: String? = nil,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.subtitle = subtitle
    self.trailing = trailing()
  }

  var body: some View {
    HStack(spacing: QaptrSpacing.medium) {
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.system(size: 13, weight: .bold))
        if let subtitle {
          Text(subtitle).font(QaptrType.caption).foregroundStyle(QaptrColor.muted)
        }
      }
      Spacer(minLength: 0)
      trailing
    }
    .padding(.horizontal, QaptrSpacing.small)
    .frame(height: 31)
    .accessibilityElement(children: .contain)
  }
}

extension QaptrTitleBar where Trailing == EmptyView {
  init(_ title: String, subtitle: String? = nil) {
    self.init(title, subtitle: subtitle) { EmptyView() }
  }
}

struct QaptrToolbar<Content: View>: View {
  @ViewBuilder let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    HStack(spacing: QaptrSpacing.small) { content }
      .padding(.horizontal, QaptrSpacing.medium)
      .frame(minHeight: 44)
      .qaptrGlassSurface(radius: QaptrRadius.button)
  }
}

struct QaptrCard<Content: View>: View {
  var padding: CGFloat = QaptrSpacing.large
  @ViewBuilder let content: Content

  init(padding: CGFloat = QaptrSpacing.large, @ViewBuilder content: () -> Content) {
    self.padding = padding
    self.content = content()
  }

  var body: some View {
    content
      .padding(padding)
      .qaptrGlassSurface()
      .accessibilityElement(children: .contain)
  }
}

struct QaptrButton: View {
  let title: String
  var systemImage: String?
  var prominent = true
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      if let systemImage {
        Label(title, systemImage: systemImage)
      } else {
        Text(title)
      }
    }
    .buttonStyle(QaptrButtonStyle(prominent: prominent))
    .accessibilityLabel(title)
  }
}

struct QaptrButtonStyle: ButtonStyle {
  var prominent = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(prominent ? .white : QaptrColor.accent)
      .padding(.horizontal, QaptrSpacing.medium)
      .frame(minHeight: 32)
      .background(
        prominent ? QaptrColor.accent : QaptrColor.accent.opacity(0.12),
        in: RoundedRectangle(cornerRadius: QaptrRadius.button, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: QaptrRadius.button, style: .continuous)
          .strokeBorder(Color.white.opacity(prominent ? 0.22 : 0.55), lineWidth: 0.5)
      }
      .opacity(configuration.isPressed ? 0.82 : 1)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
      .animation(QaptrMotion.animation(reduceMotion: reduceMotion), value: configuration.isPressed)
  }
}

enum QaptrStatusTone: Sendable {
  case neutral
  case success
  case warning
  case danger

  var color: Color {
    switch self {
    case .neutral: QaptrColor.muted
    case .success: QaptrColor.success
    case .warning: QaptrColor.warning
    case .danger: QaptrColor.danger
    }
  }
}

struct QaptrStatus: View {
  let text: String
  var tone: QaptrStatusTone = .neutral

  var body: some View {
    HStack(spacing: 6) {
      Circle().fill(tone.color).frame(width: 8, height: 8)
      Text(text).font(QaptrType.body).foregroundStyle(QaptrColor.secondaryInk)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Status: \(text)")
  }
}

struct QaptrChip: View {
  let text: String
  var systemImage: String?

  var body: some View {
    Group {
      if let systemImage {
        Label(text, systemImage: systemImage)
      } else {
        Text(text)
      }
    }
    .font(.system(size: 12, weight: .medium))
    .foregroundStyle(QaptrColor.secondaryInk)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Color.black.opacity(0.045), in: Capsule())
    .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5))
    .accessibilityLabel(text)
  }
}

struct QaptrBrand: View {
  var compact = false

  var body: some View {
    HStack(spacing: compact ? 7 : 12) {
      ZStack {
        Circle().stroke(QaptrColor.accent, lineWidth: compact ? 2.5 : 4)
        Circle().fill(QaptrColor.accent).frame(width: compact ? 5 : 8)
      }
      .frame(width: compact ? 24 : 42, height: compact ? 24 : 42)
      Text("qaptr")
        .font(.system(size: compact ? 20 : 30, weight: .bold, design: .rounded))
        .foregroundStyle(QaptrColor.ink)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Qaptr")
  }
}

struct QaptrMark: View {
  var size: CGFloat = 28

  var body: some View {
    ZStack {
      Circle().stroke(QaptrColor.ink, lineWidth: max(1.5, size * 0.07))
      Circle().trim(from: 0.08, to: 0.67)
        .stroke(
          QaptrColor.accent,
          style: StrokeStyle(lineWidth: max(2, size * 0.12), lineCap: .round)
        )
        .rotationEffect(.degrees(-42))
      Circle().fill(QaptrColor.ink).frame(width: size * 0.22)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

struct QTitleBar: View {
  let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    HStack(spacing: 0) {
      Text(title)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Color.black.opacity(0.85))
      Spacer()
    }
    .padding(.leading, 84)
    .padding(.trailing, 12)
    .frame(height: 31)
    .background(Color.white.opacity(0.42))
    .overlay(alignment: .bottom) {
      Rectangle().fill(Color.black.opacity(0.05)).frame(height: 0.5)
    }
  }
}

struct QGlassCard<Content: View>: View {
  var padding: CGFloat = 24
  @ViewBuilder let content: Content

  init(padding: CGFloat = 24, @ViewBuilder content: () -> Content) {
    self.padding = padding
    self.content = content()
  }

  var body: some View {
    content.padding(padding).qaptrGlassSurface()
  }
}

struct QGlassButtonStyle: ButtonStyle {
  var prominent = true

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(prominent ? .white : QaptrColor.accent)
      .padding(.horizontal, prominent ? 24 : 16)
      .frame(height: prominent ? 44 : 32)
      .background {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(prominent ? QaptrColor.accent : Color.white.opacity(0.12))
          .glassEffect(
            .regular.tint(prominent ? QaptrColor.accent : nil).interactive(),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
          )
      }
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(Color.white.opacity(0.42), lineWidth: 0.7)
      }
      .shadow(color: prominent ? QaptrColor.accent.opacity(0.20) : .clear, radius: 12, y: 4)
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .opacity(configuration.isPressed ? 0.86 : 1)
  }
}

struct QToast: View {
  let text: String
  let dismiss: () -> Void

  var body: some View {
    Button(action: dismiss) {
      HStack(spacing: 10) {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(QaptrColor.success)
        Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(QaptrColor.ink)
        Spacer(minLength: 4)
        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
          .foregroundStyle(QaptrColor.muted)
      }
      .padding(.horizontal, 14).padding(.vertical, 10)
      .frame(minWidth: 230)
      .qaptrGlassSurface(radius: 14)
    }
    .buttonStyle(.plain)
  }
}

struct QScreenPicker: View {
  @Bindable var model: AppModel

  var body: some View {
    Picker("Preview state", selection: $model.screen) {
      ForEach(AppScreen.allCases) { Text($0.title).tag($0) }
    }
    .labelsHidden()
    .frame(width: 190)
    .accessibilityLabel("Preview state")
  }
}
