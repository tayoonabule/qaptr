import SwiftUI

/// A press-only feedback layer: a subtle scale-down while pressed, nothing
/// else. It adds no background, border, or color, so it composes cleanly
/// with existing modifiers such as `.underline()` and `.foregroundStyle()`
/// without changing a button's look beyond the press feedback itself.
///
/// Reduced motion removes the scale movement altogether. The system still
/// provides its native pressed-state feedback without adding custom motion.
struct TactileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1.0 : 0.97)
            .animation(
                .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == TactileButtonStyle {
    static var tactile: TactileButtonStyle { TactileButtonStyle() }
}
