import SwiftUI
import UIKit

/// The Settings wheel (the system's own `UIPickerView`: same look, inertia and snapping as before) that clicks as it
/// turns — once every time a row crosses the centre line, while the finger moves and while it coasts and snaps, like
/// the iPhone's own pickers (owner 2026-10-16: 「カチカチ音がスクロールに追従していない」). One row moved is one click;
/// a fast flick clicks at most every `minGap` seconds, so the clicks never pile up into a buzz.
///
/// SwiftUI's wheel `Picker` only reports its value once the wheel has stopped, so its click came late and only once
/// for a flick across several rows. Here the row under the centre line is read from the wheel's own scrolling lists
/// (`UITableView.indexPathForRow(at:)` at the centre, every frame while the wheel moves) from a touch until it has
/// settled; before any touch nothing clicks, so showing the current value never does. Where the lists cannot be found
/// (a future system with another inside), it clicks once per change of the chosen row instead, as before.
struct TickingWheel: UIViewRepresentable {
    /// What VoiceOver calls the wheel (目標レベル…).
    let title: String
    let options: [(value: String, label: String)]
    @Binding var selection: String
    /// A row crossed the centre line (or, without the live reading, the chosen row changed).
    let onStep: () -> Void

    /// The shortest time between two clicks (a flick crosses rows faster than this).
    static let minGap: TimeInterval = 0.045

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> TouchAwarePicker {
        let picker = TouchAwarePicker()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        picker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        picker.onTouch = { [weak picker, coordinator = context.coordinator] in
            guard let picker else { return }
            coordinator.attach(to: picker)
        }
        if let row = options.firstIndex(where: { $0.value == selection }) {
            picker.selectRow(row, inComponent: 0, animated: false)
        }
        return picker
    }

    func updateUIView(_ picker: TouchAwarePicker, context: Context) {
        let changed = context.coordinator.parent.options.map(\.value) != options.map(\.value)
            || context.coordinator.parent.options.map(\.label) != options.map(\.label)
        context.coordinator.parent = self
        if changed { picker.reloadAllComponents() }
        // Never while a finger turns it or it coasts: the value it shows then is the one being chosen.
        if !context.coordinator.isTurning,
           let row = options.firstIndex(where: { $0.value == selection }), picker.selectedRow(inComponent: 0) != row {
            context.coordinator.selectQuietly(row, in: picker)
        }
    }

    static func dismantleUIView(_ picker: TouchAwarePicker, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Tells the wheel about each touch before the wheel handles it (the live reading starts with the first one).
    final class TouchAwarePicker: UIPickerView {
        var onTouch: (() -> Void)?

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            let hit = super.hitTest(point, with: event)
            if hit != nil, event?.type == .touches { onTouch?() }
            return hit
        }
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate, UIPickerViewAccessibilityDelegate {
        var parent: TickingWheel
        /// The wheel's scrolling lists (it stacks a few, scrolled together), found at the first touch.
        private var lists: [UITableView] = []
        private weak var picker: UIPickerView?
        /// Reads the row under the centre line every frame while the wheel moves (a list's offset is not always
        /// reported: the stacked lists follow the touched one without telling, the UI tour's first try clicked never).
        private var link: CADisplayLink?
        /// Since when nothing has moved (the reading stops a moment after the wheel has settled).
        private var stillSince: CFTimeInterval?
        /// The row under the centre line as last read (nil until the first touch).
        private var centreRow: Int?
        private var lastStep: TimeInterval = 0
        /// A row is being chosen by the app itself (the current value shown): no click.
        private var quiet = false

        init(_ parent: TickingWheel) { self.parent = parent }

        /// A finger is on the wheel, or it is still coasting.
        var isTurning: Bool { lists.contains { $0.isTracking || $0.isDragging || $0.isDecelerating } }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { parent.options.count }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            parent.options.indices.contains(row) ? parent.options[row].label : nil
        }

        func pickerView(_ pickerView: UIPickerView, accessibilityLabelForComponent component: Int) -> String? { parent.title }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            guard parent.options.indices.contains(row) else { return }
            // Without the live reading, the chosen row's change is the click (as before). With it, a last change the
            // frames did not see (the wheel settled between two of them) is clicked now.
            if !quiet, row != centreRow, lists.isEmpty || centreRow != nil {
                centreRow = row
                step(force: true)
            }
            let value = parent.options[row].value
            if value != parent.selection { parent.selection = value }
        }

        func selectQuietly(_ row: Int, in picker: UIPickerView) {
            quiet = true
            picker.selectRow(row, inComponent: 0, animated: false)
            if !lists.isEmpty { centreRow = row }
            quiet = false
        }

        /// A finger touched the wheel: find its lists (once) and read the centre row every frame until it settles.
        func attach(to picker: UIPickerView) {
            self.picker = picker
            if lists.isEmpty {
                lists = Self.tables(in: picker)
                guard !lists.isEmpty else {
                    UITestTrace.log("wheel live reading off (no list inside the wheel)")
                    return
                }
                centreRow = readRow()
                UITestTrace.log("wheel live reading on lists=\(lists.count) row=\(centreRow.map(String.init) ?? "-")")
            }
            stillSince = nil
            guard link == nil else { return }
            let l = CADisplayLink(target: self, selector: #selector(frame(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }

        func detach() {
            link?.invalidate()
            link = nil
            lists = []
        }

        @objc private func frame(_ l: CADisplayLink) {
            guard !quiet else { return }
            if let now = readRow(), now != centreRow {
                centreRow = now
                step(force: false)
                stillSince = nil
            }
            if isTurning {
                stillSince = nil
            } else if let since = stillSince {
                // Settled (the snap after the finger lifts included): stop reading until the next touch.
                if l.timestamp - since > 0.6 {
                    link?.invalidate()
                    link = nil
                }
            } else {
                stillSince = l.timestamp
            }
        }

        /// The row under the wheel's centre line right now: read from the list the finger moves (or that coasts),
        /// else from the one drawn under the centre line.
        private func readRow() -> Int? {
            guard let picker else { return nil }
            let centre = CGPoint(x: picker.bounds.midX, y: picker.bounds.midY)
            let moving = lists.first { $0.isTracking || $0.isDragging || $0.isDecelerating }
            let under = lists.first { $0.convert($0.bounds, to: picker).contains(centre) }
            guard let table = moving ?? under ?? lists.first else { return nil }
            guard let path = table.indexPathForRow(at: picker.convert(centre, to: table)),
                  parent.options.indices.contains(path.row) else { return nil }
            return path.row
        }

        /// One click (and the selection tap). A flick's clicks closer than `minGap` are skipped; `force` never is.
        private func step(force: Bool) {
            let now = ProcessInfo.processInfo.systemUptime
            guard force || now - lastStep >= TickingWheel.minGap else { return }
            lastStep = now
            UITestTrace.log("wheel click \(force ? "chosen" : "centre") row=\(centreRow.map(String.init) ?? "-")")
            parent.onStep()
        }

        private static func tables(in view: UIView) -> [UITableView] {
            var out: [UITableView] = []
            var queue: [UIView] = [view]
            while !queue.isEmpty {
                let v = queue.removeFirst()
                if let t = v as? UITableView { out.append(t); continue }
                queue.append(contentsOf: v.subviews)
            }
            return out
        }
    }
}
