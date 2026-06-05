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

    /// Paper background plus the mood's faint grid (terminal squares / Swiss
    /// columns), drawn behind the content.
    func moodPaper(_ theme: Theme) -> some View {
        background {
            ZStack {
                theme.paper
                if theme.colorScheme == .light {
                    // Faint paper grain — the design's layered radial highlights.
                    RadialGradient(colors: [.white.opacity(0.35), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 520)
                    RadialGradient(colors: [.black.opacity(0.02), .clear],
                                   center: .bottomTrailing, startRadius: 0, endRadius: 480)
                }
                MoodGrid(theme: theme)
            }
            .ignoresSafeArea()
        }
    }

    /// Wraps content in the mood's "card on paper" treatment — fill + border +
    /// corner radius + shadow — so each mood's *shape* shows, not just its
    /// colors: Paper = rounded with a soft shadow, Swiss/Terminal = square
    /// hairline, Neubrutalist = thick black border with a hard offset shadow.
    func moodCard(_ theme: Theme, fill: Color? = nil, selected: Bool = false) -> some View {
        modifier(MoodCardModifier(theme: theme, fill: fill, selected: selected))
    }
}

/// Draws the mood's background grid with `Canvas`. Non-interactive.
private struct MoodGrid: View {
    let theme: Theme

    var body: some View {
        Canvas { context, size in
            switch theme.grid {
            case .none:
                break
            case .squares(let step):
                draw(in: context, size: size, color: theme.line.opacity(0.6), verticalStep: step, horizontalStep: step)
            case .columns(let count):
                let step = size.width / CGFloat(max(1, count))
                draw(in: context, size: size, color: theme.line.opacity(0.12), verticalStep: step, horizontalStep: nil)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(in context: GraphicsContext, size: CGSize, color: Color, verticalStep: CGFloat, horizontalStep: CGFloat?) {
        var x = verticalStep
        while x < size.width {
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(line, with: .color(color), lineWidth: 1)
            x += verticalStep
        }
        if let horizontalStep {
            var y = horizontalStep
            while y < size.height {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(color), lineWidth: 1)
                y += horizontalStep
            }
        }
    }
}

private struct MoodCardModifier: ViewModifier {
    let theme: Theme
    let fill: Color?
    let selected: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius)
        let surface = fill ?? theme.paperRaised
        content
            .background(surface)
            .clipShape(shape)
            // The shadow is cast by a shape *behind* the content — never by the
            // text — so a hard offset shadow doesn't duplicate the text.
            .background { shape.fill(surface).themeShadow(theme.shadow) }
            .overlay(
                shape.strokeBorder(
                    selected ? theme.accent : theme.edge,
                    lineWidth: selected ? max(theme.borderWidth, 2) : theme.borderWidth
                )
            )
    }
}
