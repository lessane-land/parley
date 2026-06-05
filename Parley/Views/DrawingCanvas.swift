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

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput        // Pencil *or* finger, so it's usable without a Pencil too
        canvas.backgroundColor = .clear         // let the themed paper show through
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        context.coordinator.canvas = canvas

        // Default to a pen in the mood's ink color (the user can change it in
        // the tool picker).
        canvas.tool = PKInkingTool(.pen, color: UIColor(inkColor), width: 4)

        // Load any previously saved strokes.
        if let data, let drawing = try? PKDrawing(data: data) {
            canvas.drawing = drawing
        }

        // The floating tool picker (pens, eraser, colors, ruler).
        let picker = context.coordinator.toolPicker
        picker.setVisible(true, forFirstResponder: canvas)
        picker.addObserver(canvas)
        // Becoming first responder is what makes the picker appear; defer a tick
        // so it happens after the view is in the window.
        DispatchQueue.main.async { canvas.becomeFirstResponder() }

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // Keep the coordinator's notion of "the binding" current so its delegate
        // callback writes to the right place. We intentionally do NOT reload
        // `canvas.drawing` from `data` here — the detail view is rebuilt per note
        // (via `.id`), so each note already gets a fresh canvas in `makeUIView`,
        // and reloading mid-stroke would fight the user's input.
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DrawingCanvas
        let toolPicker = PKToolPicker()
        weak var canvas: PKCanvasView?

        init(_ parent: DrawingCanvas) { self.parent = parent }

        /// Fired whenever the strokes change. Serialize and push back through the
        /// binding → SwiftData persists it.
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.data = canvasView.drawing.dataRepresentation()
        }
    }
}
#endif
