import SwiftUI

/// A press-only feedback layer: a subtle scale-down while pressed, nothing
/// else. It adds no background, border, or color, so it composes cleanly
/// with existing modifiers such as `.underline()` and `.foregroundStyle()`
/// without changing a button's look beyond the press feedback itself.
///
/// Reduced motion is respected the same way `RootView`'s existing transition
/// is: when `accessibilityReduceMotion` is set, the scale change still
/// applies (so pressed state remains visible for feedback) but with a
/// near-instant animation instead of an eased one, avoiding perceptible
/// motion.
struct TactileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(
                reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == TactileButtonStyle {
    static var tactile: TactileButtonStyle { TactileButtonStyle() }
}
