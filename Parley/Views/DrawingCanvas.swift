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

    /// When on, a freehand stroke that clearly traces a rectangle or oval is
    /// swapped for a clean, movable shape. (Apple's own shape recognition isn't
    /// available to third-party `PKCanvasView`s, so we do it ourselves.)
    var recognizeShapes: Bool = true

    /// Called when a stroke was recognized as a shape: its kind and rect in the
    /// canvas's *page* (content) coordinates, so the overlay can drop a `CanvasItem`
    /// that stays anchored to the page as it scrolls.
    var onRecognizeShape: ((CanvasItem.Kind, CGRect) -> Void)? = nil

    /// Reports the canvas's scroll position so the items overlay can scroll *with*
    /// the ink (otherwise a pasted image/shape stays pinned to the screen).
    var onScroll: ((CGPoint) -> Void)? = nil

    /// When false, the canvas does its own scrolling. When the note surface wraps
    /// everything (text + ink + items) in one outer scroll view, set this false so
    /// the canvas is a fixed-height drawing layer and the *outer* scroll moves it —
    /// making text, ink, and pictures scroll together as one page.
    var scrollEnabled: Bool = true

    /// While `scrollEnabled` is false, reports the ink's lowest point so the owner
    /// can grow the page height to keep room to draw.
    var onContentHeight: ((CGFloat) -> Void)? = nil

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        // `.default` follows the system: when an Apple Pencil is paired the Pencil
        // draws and a finger scrolls/selects (so finger drags still pan the page and
        // move shapes) — and, crucially, it surfaces the tool picker's "Draw with
        // Finger" toggle so the user can opt into finger drawing if they want. (We
        // previously forced `.pencilOnly`, which hid that option.)
        canvas.drawingPolicy = .default
        canvas.backgroundColor = .clear         // overlays the typed notes; paper shows through
        canvas.isOpaque = false
        // When the outer surface scrolls, the canvas itself must not (it's a fixed
        // drawing layer the outer scroll moves).
        canvas.isScrollEnabled = scrollEnabled
        canvas.alwaysBounceVertical = scrollEnabled
        canvas.showsVerticalScrollIndicator = scrollEnabled
        // PKCanvasView is a UIScrollView; its default `.automatic` inset behavior
        // folds the surrounding safe area into an *adjusted content inset*, which
        // shoves a saved drawing to the right (blank gutter on the left, strokes
        // clipped on the right) while the typed layer underneath stays put. Pin it
        // so the ink lines up with the text on every open.
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.contentInset = .zero
        canvas.delegate = context.coordinator
        context.coordinator.canvas = canvas

        // Default to a pen in the mood's ink color (the user can change it in
        // the tool picker).
        canvas.tool = PKInkingTool(.pen, color: UIColor(inkColor), width: 4)

        // Load any previously saved strokes.
        if let data, let drawing = try? PKDrawing(data: data) {
            canvas.drawing = drawing
        }
        context.coordinator.lastStrokeCount = canvas.drawing.strokes.count

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
        if scrollEnabled {
            Self.growContent(canvas)
        } else {
            // Outer scroll owns scrolling: pin the canvas's content to its bounds.
            canvas.isScrollEnabled = false
            if canvas.contentSize != canvas.bounds.size {
                canvas.contentSize = canvas.bounds.size
            }
        }
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

        /// Stroke count after the last settled change, so on tool-end we can tell a
        /// freehand stroke was just added (vs. an erase or our own edit).
        var lastStrokeCount = 0

        init(_ parent: DrawingCanvas) { self.parent = parent }

        /// Fired whenever the strokes change. Serialize and push back through the
        /// binding → SwiftData persists it.
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.data = canvasView.drawing.dataRepresentation()
            if parent.scrollEnabled {
                DrawingCanvas.growContent(canvasView)
            } else {
                let bottom = canvasView.drawing.bounds.isNull ? 0 : canvasView.drawing.bounds.maxY
                parent.onContentHeight?(bottom)
            }
        }

        /// The user actually started drawing — bring the canvas (and its tool
        /// picker) up *now*, rather than us forcing first responder on every
        /// update. This is what lets the Pencil reactivate the canvas after the
        /// keyboard was used on the title, without fighting text fields.
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            if !canvasView.isFirstResponder { canvasView.becomeFirstResponder() }
            toolPicker.setVisible(true, forFirstResponder: canvasView)
        }

        /// On pencil-up, if the just-finished stroke clearly traces a shape, swap
        /// the freehand ink for a clean shape the user can move and resize.
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            defer { lastStrokeCount = canvasView.drawing.strokes.count }
            guard parent.recognizeShapes else { return }
            let strokes = canvasView.drawing.strokes
            // Only a single, freshly-added stroke is a shape candidate.
            guard strokes.count == lastStrokeCount + 1, let stroke = strokes.last,
                  let (kind, pageRect) = ShapeRecognizer.classify(stroke) else { return }

            var remaining = strokes
            remaining.removeLast()
            let cleaned = PKDrawing(strokes: remaining)
            canvasView.drawing = cleaned
            parent.data = cleaned.dataRepresentation()
            DrawingCanvas.growContent(canvasView)

            // Hand back page (content) coords; the overlay anchors to the page and
            // applies the scroll offset itself.
            parent.onRecognizeShape?(kind, pageRect)
        }

        /// PKCanvasViewDelegate refines UIScrollViewDelegate, so this fires as the
        /// canvas scrolls — we forward the offset so the items overlay tracks it.
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.onScroll?(scrollView.contentOffset)
        }
    }
}

/// Lightweight, on-device shape recognition for a single Pencil stroke. No ML —
/// just geometry: a large, *closed* stroke is fit against a rectangle and an oval,
/// and the better fit wins (if either is clean enough). Open strokes and small
/// marks (handwriting) are left as ink.
enum ShapeRecognizer {
    static func classify(_ stroke: PKStroke) -> (CanvasItem.Kind, CGRect)? {
        let path = stroke.path
        guard path.count >= 6 else { return nil }

        var pts: [CGPoint] = []
        pts.reserveCapacity(path.count)
        for i in 0..<path.count { pts.append(path[i].location.applying(stroke.transform)) }

        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for p in pts {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        let w = maxX - minX, h = maxY - minY
        let diag = hypot(w, h)
        // Ignore small marks (letters, dots) and near-degenerate (flat) strokes.
        guard diag > 54, w > 26, h > 26 else { return nil }

        // Must be roughly closed (end returns near start) to be a rect/oval. A bit
        // lenient so a hand-drawn shape with a small gap still counts.
        let first = pts.first!, last = pts.last!
        guard hypot(last.x - first.x, last.y - first.y) < diag * 0.30 else { return nil }

        let cx = minX + w / 2, cy = minY + h / 2
        let ax = w / 2, ay = h / 2
        var ellErr: CGFloat = 0, rectErr: CGFloat = 0
        for p in pts {
            let nx = (p.x - cx) / ax, ny = (p.y - cy) / ay
            ellErr += abs((nx * nx + ny * ny).squareRoot() - 1)   // distance from unit circle
            rectErr += abs(max(abs(nx), abs(ny)) - 1)             // distance from unit square
        }
        let n = CGFloat(pts.count)
        ellErr /= n; rectErr /= n
        // Require a reasonably clean trace; otherwise keep the freehand ink.
        guard min(ellErr, rectErr) < 0.26 else { return nil }

        let rect = CGRect(x: minX, y: minY, width: w, height: h)
        return (ellErr <= rectErr ? .ellipse : .rectangle, rect)
    }
}
#endif
