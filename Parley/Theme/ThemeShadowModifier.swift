import SwiftUI

/// Applies a `ThemeShadow` if the current mood defines one (paper, neubrutalist),
/// and is a no-op when it's `nil` (terminal, swiss). Pulled into a `ViewModifier`
/// so call sites stay tidy: `.themeShadow(theme.shadow)`.
private struct ThemeShadowModifier: ViewModifier {
    let shadow: ThemeShadow?

    func body(content: Content) -> some View {
        if let shadow {
            content.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
        } else {
            content
        }
    }
}

extension View {
    func themeShadow(_ shadow: ThemeShadow?) -> some View {
        modifier(ThemeShadowModifier(shadow: shadow))
    }
}
