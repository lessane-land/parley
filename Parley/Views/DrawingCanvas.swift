#if os(iOS)
import SwiftUI
import PencilKit

/// Bridges PencilKit's UIKit `PKCanvasView` into SwiftUI.
///
/// SwiftUI has no native drawing canvas, so we wrap the UIKit view with
/// `UIViewRepresentable` — the standard escape hatch for using a UIKit/AppKit
/// view from SwiftUI. The protocol has three jobs:
///   • `makeUIView`      — build the view once,
///   • `updateUIView`    — push SwiftUI state changes into it,
///   • `Coordinator`     — receive delegate callbacks back out (here: "the
///                          drawing changed", which we persist).
///
/// This file is wrapped in `#if os(iOS)` because PencilKit's canvas is an iOS
/// (iPad/iPhone) thing; the Mac build never compiles it.
struct DrawingCanvas: UIViewRepresentable {
    /// Two-way binding to the note's serialized `PKDrawing`. Writing here flows
    /// straight into SwiftData (autosaved).
    @Binding var data: Data?

    /// The mood's ink color, used as the default pen color.
    var inkColor: Color

    /// Whether this canvas is the active input layer (Draw mode). When false the
    /// tool picker hides and the canvas resigns first responder so the text layer
    /// underneath can be typed in.
    var isActive: Bool = true

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        // Pencil draws; a finger *scrolls* instead of drawing. PKCanvasView is a
        // scroll view, so with `.pencilOnly` one-finger drags pan the canvas —
        // which is what lets handwriting extend past one screen.
        canvas.drawingPolicy = .pencilOnly
        canvas.backgroundColor = .clear         // overlays the typed notes; paper shows through
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = true      // makes the scrollability discoverable
        canvas.showsVerticalScrollIndicator = true
        canvas.delegate = context.coordinator
        context.coordinator.canvas = canvas

        // Default to a pen in the mood's ink color (the user can change it in
        // the tool picker).
        canvas.tool = PKInkingTool(.pen, color: UIColor(inkColor), width: 4)

        // Load any previously saved strokes.
        if let data, let drawing = try? PKDrawing(data: data) {
            canvas.drawing = drawing
        }

        context.coordinator.toolPicker.addObserver(canvas)
        applyActive(isActive, to: canvas, context: context)
        context.coordinator.appliedActive = isActive

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // Keep the coordinator's binding current so its delegate writes to the
        // right place. We don't reload `canvas.drawing` from `data` — the detail
        // is rebuilt per note (via `.id`), so each note gets a fresh canvas.
        context.coordinator.parent = self
        // Only react to an actual Type⟷Draw change. Re-applying on every update
        // would keep stealing first responder back from text fields (the title,
        // a speaker name…), so their keyboard could never appear on iPad.
        if context.coordinator.appliedActive != isActive {
            context.coordinator.appliedActive = isActive
            applyActive(isActive, to: canvas, context: context)
        }
        Self.growContent(canvas)
    }

    /// Grow the scrollable content so there's always room below the lowest stroke
    /// to keep writing (and to scroll). PKCanvasView doesn't auto-extend, so we
    /// size it to the drawing's extent plus roughly half a screen of headroom.
    static func growContent(_ canvas: PKCanvasView) {
        let viewport = canvas.bounds.height
        guard viewport > 0 else { return }
        let drawingBottom = canvas.drawing.bounds.isNull ? 0 : canvas.drawing.bounds.maxY
        let height = max(viewport, drawingBottom + viewport * 0.5)
        if abs(canvas.contentSize.height - height) > 1 {
            canvas.contentSize = CGSize(width: canvas.bounds.width, height: height)
        }
    }

    /// Show/hide the tool picker and grab/release first responder with the mode.
    private func applyActive(_ active: Bool, to canvas: PKCanvasView, context: Context) {
        let picker = context.coordinator.toolPicker
        picker.setVisible(active, forFirstResponder: canvas)
        if active, !canvas.isFirstResponder {
            DispatchQueue.main.async { canvas.becomeFirstResponder() }
        } else if !active, canvas.isFirstResponder {
            DispatchQueue.main.async { canvas.resignFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DrawingCanvas
        let toolPicker = PKToolPicker()
        weak var canvas: PKCanvasView?
        /// The last Draw/Type state we acted on, so `updateUIView` only reacts to
        /// real changes (and never re-steals first responder from a text field).
        var appliedActive: Bool?

        init(_ parent: DrawingCanvas) { self.parent = parent }

        /// Fired whenever the strokes change. Serialize and push back through the
        /// binding → SwiftData persists it.
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.data = canvasView.drawing.dataRepresentation()
            DrawingCanvas.growContent(canvasView)
        }

        /// The user actually started drawing — bring the canvas (and its tool
        /// picker) up *now*, rather than us forcing first responder on every
        /// update. This is what lets the Pencil reactivate the canvas after the
        /// keyboard was used on the title, without fighting text fields.
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            if !canvasView.isFirstResponder { canvasView.becomeFirstResponder() }
            toolPicker.setVisible(true, forFirstResponder: canvasView)
        }
    }
}
#endif
