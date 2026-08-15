import SwiftUI

/// The one press-feedback layer used by every plain-content button in the
/// app: a subtle scale-down while pressed, nothing else. It adds no
/// background, border, or color, so it composes cleanly with existing
/// modifiers such as `.underline()` and `.foregroundStyle()` without
/// changing a button's look beyond the press feedback itself.
///
/// Reduced motion removes the scale movement altogether. The system still
/// provides its native pressed-state feedback without adding custom motion.
struct TactileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1.0 : 0.97)
            .animation(QaptrMotion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TactileButtonStyle {
    static var tactile: TactileButtonStyle { TactileButtonStyle() }
}

/// A quiet text-only button: no fill, no border. Used for the single
/// secondary action on a row (Remove, Back) where a bordered control would
/// read as competing with the row's own content.
struct QaptrQuietButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QaptrType.body(12.5))
            .foregroundStyle(isEnabled ? Color.qaptrInkSoft : Color.qaptrInkSoft.opacity(0.4))
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1.0 : 0.97)
            .animation(QaptrMotion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == QaptrQuietButtonStyle {
    static var qaptrQuiet: QaptrQuietButtonStyle { QaptrQuietButtonStyle() }
}

/// The single filled, accent-colored button used for the one primary action
/// on a screen (Continue, Finish, Connect).
struct QaptrPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QaptrType.title(13))
            .foregroundStyle(Color.qaptrAccentInk)
            .padding(.horizontal, QaptrSpace.lg)
            .padding(.vertical, QaptrSpace.sm)
            .background(
                Color.qaptrAccent.opacity(isEnabled ? 1 : 0.35),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1.0 : 0.97)
            .animation(QaptrMotion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == QaptrPrimaryButtonStyle {
    static var qaptrPrimary: QaptrPrimaryButtonStyle { QaptrPrimaryButtonStyle() }
}

/// A hairline-outlined button for a secondary but still deliberate action
/// (Allow, Try again, Add).
struct QaptrOutlineButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QaptrType.title(12.5))
            .foregroundStyle(isEnabled ? Color.qaptrInk : Color.qaptrInkSoft.opacity(0.5))
            .padding(.horizontal, QaptrSpace.md)
            .padding(.vertical, QaptrSpace.xs)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.qaptrHairline, lineWidth: 1)
            }
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1.0 : 0.97)
            .animation(QaptrMotion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == QaptrOutlineButtonStyle {
    static var qaptrOutline: QaptrOutlineButtonStyle { QaptrOutlineButtonStyle() }
}
