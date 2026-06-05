import SwiftUI

/// A resolved set of design tokens for one mood. Views read these instead of
/// hard-coding colors, so switching mood restyles the whole app from one place.
///
/// These map 1:1 to the `--pk-*` CSS custom properties in the Parley design.
/// `struct` (value type) is right here: a theme is just immutable data we copy
/// around freely; there's nothing to mutate or share by reference.
struct Theme: Equatable {
    // Surfaces (paper system)
    var paper: Color        // --pk-paper        : the canvas
    var paperRaised: Color  // --pk-paper-rec    : cards / raised surfaces
    var paperSunk: Color    // --pk-paper-sink   : recessed panels (sidebar, transcript)
    var edge: Color         // --pk-edge         : hairline / card border

    // Ink neutrals
    var ink: Color          // --pk-ink          : primary text
    var ink2: Color         // --pk-ink-2        : body text
    var inkSoft: Color      // --pk-ink-soft     : secondary
    var inkFaint: Color     // --pk-ink-faint    : tertiary / timestamps
    var inkGhost: Color     // --pk-ink-ghost    : faint marks
    var line: Color         // --pk-line         : dividers

    // The single accent
    var accent: Color       // --pk-accent
    var accentInk: Color    // --pk-accent-ink   : darker accent for text on tint
    var accentTint: Color   // --pk-accent-tint  : soft accent fill
    var accentLine: Color   // --pk-accent-line  : accent hairline / focus ring

    // Recording status (a functional signal, not a brand color)
    var rec: Color          // --pk-rec

    // Geometry
    var cornerRadius: CGFloat   // --pk-radius
    var borderWidth: CGFloat    // --pk-border-w
    var shadow: ThemeShadow?    // --pk-shadow-card (nil = no shadow)

    // Typography roles. We express the design's font *intent* via SwiftUI's
    // font "design" (serif / monospaced / default-grotesk). See note in Mood.swift
    // about the named fonts (Newsreader, Space Grotesk, …) vs. these system roles.
    var titleDesign: Font.Design       // headings / note titles
    var titleWeight: Font.Weight
    var noteDesign: Font.Design         // the user's own note text
    var transcriptDesign: Font.Design   // live transcript (used from Phase 2 on)

    /// Whether the mood is fundamentally light or dark. Drives the window's
    /// `preferredColorScheme` so system chrome (status bar, etc.) matches.
    var colorScheme: ColorScheme
}

/// A drop shadow expressed the way CSS does it: color + blur radius + offset.
/// The neubrutalist mood uses a hard shadow (radius 0, offset 4/4), the paper
/// mood a soft one; terminal and swiss have none.
struct ThemeShadow: Equatable {
    var color: Color
    var radius: CGFloat
    var x: CGFloat
    var y: CGFloat
}
