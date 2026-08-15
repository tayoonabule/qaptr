import SwiftUI

/// The one press-feedback layer used by every plain-content button in the app.
/// It adds a restrained paper-mist hover/pressed surface without changing the
/// content's layout or accessibility semantics.
///
/// Reduced motion removes the scale movement altogether. The system still
/// provides its native pressed-state feedback without adding custom motion.
struct TactileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, QaptrSpace.sm)
            .padding(.vertical, QaptrSpace.xs)
            .background(
                configuration.isPressed ? Color.qaptrPaperMist : Color.clear,
                in: RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous)
            )
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1.0 : 0.98)
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
            .foregroundStyle(isEnabled ? Color.qaptrSlate : Color.qaptrInkMuted)
            .padding(.horizontal, QaptrSpace.sm)
            .padding(.vertical, QaptrSpace.xs)
            .background(
                configuration.isPressed ? Color.qaptrPaperMist : Color.clear,
                in: RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous)
            )
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1.0 : 0.98)
            .animation(QaptrMotion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == QaptrQuietButtonStyle {
    static var qaptrQuiet: QaptrQuietButtonStyle { QaptrQuietButtonStyle() }
}

/// The single filled black button used for the one primary action on a screen
/// (Continue, Finish, Connect).
struct QaptrPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QaptrType.title(13))
            .foregroundStyle(Color.white)
            .padding(.horizontal, QaptrSpace.lg)
            .padding(.vertical, QaptrSpace.md)
            .background(
                Color.qaptrPrimaryAction.opacity(isEnabled ? 1 : 0.35),
                in: RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous)
            )
            .shadow(color: Color.black.opacity(isEnabled ? 0.05 : 0), radius: 1, y: 1)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1.0 : 0.98)
            .animation(QaptrMotion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == QaptrPrimaryButtonStyle {
    static var qaptrPrimary: QaptrPrimaryButtonStyle { QaptrPrimaryButtonStyle() }
}

/// A bordered button for a secondary but still deliberate action (Allow, Try
/// again, Add).
struct QaptrOutlineButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QaptrType.title(12.5))
            .foregroundStyle(isEnabled ? Color.qaptrInk : Color.qaptrInkMuted)
            .padding(.horizontal, QaptrSpace.lg)
            .padding(.vertical, QaptrSpace.md)
            .background(Color.qaptrSurface, in: RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: QaptrRadius.control, style: .continuous)
                    .strokeBorder(Color.qaptrHairline, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.65)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1.0 : 0.98)
            .animation(QaptrMotion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == QaptrOutlineButtonStyle {
    static var qaptrOutline: QaptrOutlineButtonStyle { QaptrOutlineButtonStyle() }
}

/// Native inputs use the design system's emphasized black 1px outline rather
/// than the platform's default gray rounded field.
struct QaptrTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(QaptrType.body())
            .foregroundStyle(Color.qaptrInk)
            .padding(.horizontal, QaptrSpace.md)
            .padding(.vertical, QaptrSpace.sm)
            .background(Color.qaptrSurface, in: RoundedRectangle(cornerRadius: QaptrRadius.input, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: QaptrRadius.input, style: .continuous)
                    .strokeBorder(Color.qaptrInputBorder, lineWidth: 1)
            }
    }
}

extension TextFieldStyle where Self == QaptrTextFieldStyle {
    static var qaptr: QaptrTextFieldStyle { QaptrTextFieldStyle() }
}
