import SwiftUI
import UIKit

// The word page's picture: a sideways pan (the next photo comes in under the finger) and a long press (「表示する写真」),
// as UIKit recognizers (`UIGestureRecognizerRepresentable`, iOS 18). SwiftUI's own `DragGesture` and `LongPressGesture`,
// even as simultaneous gestures, kept the page from scrolling when the finger started on the picture (owner
// 2026-11-01: 「切り抜きの上をスクロールしても下に行かない」; `WordOpenTests.test_scrollPageDownAndUp` showed the word
// card not moving). A UIKit pan that begins only for a mostly sideways movement fails for an up-and-down one, and the
// page's scroll view takes the touch.

/// A sideways pan on the picture. Begins only when the finger moves more across than up or down.
struct SidewaysPan: UIGestureRecognizerRepresentable {
    var onBegan: () -> Void
    /// The finger's sideways travel so far.
    var onChanged: (CGFloat) -> Void
    /// The travel and the sideways speed (points per second) when the finger lifts.
    var onEnded: (CGFloat, CGFloat) -> Void
    var onCancelled: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let x = pan.translation(in: pan.view).x
        switch pan.state {
        case .began:
            onBegan()
            onChanged(x)
        case .changed:
            onChanged(x)
        case .ended:
            onEnded(x, pan.velocity(in: pan.view).x)
        case .cancelled, .failed:
            onCancelled()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y) * 1.2
        }

        /// The page's scroll waits for this pan to decide: sideways → the photo turns; up and down → this pan fails at
        /// once (above) and the page scrolls.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}

/// A long press on the picture. Fails as soon as the finger moves, so a drag that begins on the picture scrolls the page.
struct HoldPress: UIGestureRecognizerRepresentable {
    /// The press began (held long enough) / ended.
    var onPressing: (Bool) -> Void
    var onLongPress: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let press = UILongPressGestureRecognizer()
        press.minimumPressDuration = 0.45
        press.delegate = context.coordinator
        return press
    }

    func handleUIGestureRecognizerAction(_ press: UILongPressGestureRecognizer, context: Context) {
        switch press.state {
        case .began:
            onPressing(true)
            onLongPress()
        case .ended, .cancelled, .failed:
            onPressing(false)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
