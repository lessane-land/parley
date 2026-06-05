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

    /// Wraps content in the mood's "card on paper" treatment — fill + border +
    /// corner radius + shadow — so each mood's *shape* shows, not just its
    /// colors: Paper = rounded with a soft shadow, Swiss/Terminal = square
    /// hairline, Neubrutalist = thick black border with a hard offset shadow.
    func moodCard(_ theme: Theme, fill: Color? = nil, selected: Bool = false) -> some View {
        modifier(MoodCardModifier(theme: theme, fill: fill, selected: selected))
    }
}

private struct MoodCardModifier: ViewModifier {
    let theme: Theme
    let fill: Color?
    let selected: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius)
        content
            .background(fill ?? theme.paperRaised, in: shape)
            .overlay(
                shape.strokeBorder(
                    selected ? theme.accent : theme.edge,
                    lineWidth: selected ? max(theme.borderWidth, 2) : theme.borderWidth
                )
            )
            .themeShadow(theme.shadow)
    }
}
