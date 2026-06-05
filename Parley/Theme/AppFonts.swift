import CoreText
import Foundation

/// Registers the app's bundled fonts at launch.
///
/// We register at runtime (CoreText) instead of via `Info.plist`'s `UIAppFonts`
/// for two reasons: it works identically on iOS and macOS, and it needs no
/// changes to the auto-generated `Info.plist`. Called once from `ParleyApp.init`.
///
/// `Font.custom` falls back to the system font when a name isn't found, so if a
/// face ever fails to register the app still renders — just with system type.
enum AppFonts {
    static func registerAll() {
        // The fonts live in the app bundle. Depending on how the folder is added,
        // they may land at the Resources root or inside a "Fonts" subdirectory —
        // look in both and de-duplicate.
        let flat = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        let nested = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        let urls = Array(Set(flat + nested))
        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // A duplicate registration (e.g. across SwiftUI previews) is
                // harmless; only surface anything unexpected while debugging.
                #if DEBUG
                if let error = error?.takeRetainedValue() {
                    print("Font registration note for \(url.lastPathComponent): \(error)")
                }
                #endif
            }
        }
    }
}
