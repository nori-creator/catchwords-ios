import SwiftUI
import UIKit

/// Scrolls the home page while a photo is carried to its top or bottom edge (owner 2026-10-14: 「画像が画面のうえに
/// 達したら自動的にページもうえにスクロールされて画像を自由に動かせるようにして。今は完了ボタンを押して、自分で
/// ページをスクロールしてからまた長押しで…」).
///
/// The page's scroll view is frozen while rearranging (so the finger moves the photo, not the page); this moves it
/// from code instead. `scrolled` is how far the page moved since the photo was taken: the photo adds it to the finger's
/// own movement, so it stays under the finger while the page runs.
@Observable
final class AlbumAutoScroll {
    /// Points the page scrolled since the current photo was taken (+ = the page moved up, showing what is below).
    private(set) var scrolled: CGFloat = 0

    @ObservationIgnored weak var scrollView: UIScrollView?
    @ObservationIgnored private var fingerY: CGFloat?
    @ObservationIgnored private var task: Task<Void, Never>?

    /// How near the edge (points) the finger starts the page moving, and the fastest step (points per frame).
    private static let zone: CGFloat = 90
    private static let maxStep: CGFloat = 16

    /// A photo was taken: nothing scrolled yet.
    func begin() {
        stop()
        scrolled = 0
    }

    /// The finger is at this height on the screen (window points).
    func finger(atWindowY y: CGFloat) {
        fingerY = y
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    /// The photo was let go: returns how far the page moved, and starts from 0 next time.
    @discardableResult
    func end() -> CGFloat {
        stop()
        let s = scrolled
        scrolled = 0
        return s
    }

    private func stop() {
        task?.cancel()
        task = nil
        fingerY = nil
    }

    private func tick() {
        guard let y = fingerY, let sv = scrollView, let window = sv.window else { return }
        let frame = sv.convert(sv.bounds, to: window)
        let inset = sv.adjustedContentInset
        let top = frame.minY + inset.top
        let bottom = frame.maxY - inset.bottom
        var step: CGFloat = 0
        if y < top + Self.zone {
            step = -Self.maxStep * min(1, (top + Self.zone - y) / Self.zone)
        } else if y > bottom - Self.zone {
            step = Self.maxStep * min(1, (y - (bottom - Self.zone)) / Self.zone)
        }
        guard step != 0 else { return }
        let minY = -inset.top
        let maxY = max(minY, sv.contentSize.height - sv.bounds.height + inset.bottom)
        let from = sv.contentOffset.y
        let to = min(maxY, max(minY, from + step))
        guard to != from else { return }
        sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: to), animated: false)
        scrolled += to - from
    }
}

/// Finds the UIKit scroll view a SwiftUI `ScrollView`'s content sits in (put it in the content's background).
struct ScrollViewFinder: UIViewRepresentable {
    let onFind: (UIScrollView) -> Void

    func makeUIView(context: Context) -> Probe {
        let v = Probe()
        v.onFind = onFind
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: Probe, context: Context) {}

    final class Probe: UIView {
        var onFind: ((UIScrollView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                var v = self?.superview
                while let s = v {
                    if let sv = s as? UIScrollView {
                        self?.onFind?(sv)
                        return
                    }
                    v = s.superview
                }
            }
        }
    }
}
