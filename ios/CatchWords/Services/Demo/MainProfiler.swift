#if DEBUG
import Darwin
import Foundation
import QuartzCore

/// What the main thread does during a catch's landing, measured instead of guessed (owner 2026-11-27: 「適当に直す
/// のではなく根本的に原因を特定し」 — the add to 図鑑 still stopped for most of a second as the sticker hit its square).
///
/// While a landing plays (`-uiProfile YES`, DEBUG builds launched with `-uiDemo` only), a thread of its own reads the
/// main thread's call stack every 2 ms (`MainStackSampler`: the main thread is paused for the few microseconds the
/// return addresses take to copy). When the landing ends, the samples are named and summed into the UI tests' trace,
/// cut at the landing's own steps (`mark`): for each part, how much of it the main thread was busy, the longest
/// stretch it was busy without a break (a frozen picture), what it was doing then, and where its time went in all
/// (each function counted once per sample it is on the stack in, the app's own functions apart).
nonisolated enum MainProfiler {
    static var isOn: Bool { DemoBackend.isOn && UserDefaults.standard.bool(forKey: "uiProfile") }

    /// Starts sampling (nothing happens when already sampling or not asked for).
    static func begin(_ label: String) {
        guard isOn else { return }
        Recorder.shared.begin(label)
    }

    /// A step of what is being measured (`launch`, `impact` …): the summary is cut at these.
    static func mark(_ name: String) {
        guard isOn else { return }
        Recorder.shared.mark(name)
    }

    /// Stops sampling and writes the summary into the trace (off the main thread).
    static func end() {
        guard isOn else { return }
        Recorder.shared.end()
    }

    nonisolated private final class Recorder: @unchecked Sendable {
        static let shared = Recorder()
        private let lock = NSLock()
        private var running = false
        private var label = ""
        private var samples: [(t: CFTimeInterval, frames: [UInt])] = []
        private var marks: [(t: CFTimeInterval, name: String)] = []
        private var started: CFTimeInterval = 0

        func begin(_ label: String) {
            lock.lock()
            guard !running else { lock.unlock(); return }
            running = true
            self.label = label
            samples = []
            samples.reserveCapacity(4000)
            marks = []
            started = CACurrentMediaTime()
            lock.unlock()
            let thread = Thread { [self] in loop() }
            thread.qualityOfService = .userInteractive
            thread.name = "uitest-profiler"
            thread.start()
        }

        func mark(_ name: String) {
            lock.lock()
            if running { marks.append((CACurrentMediaTime(), name)) }
            lock.unlock()
        }

        func end() {
            lock.lock()
            running = false
            lock.unlock()
        }

        private func loop() {
            while true {
                lock.lock()
                let on = running
                lock.unlock()
                guard on else { break }
                let frames = MainStackSampler.sample(maxFrames: 120)
                let t = CACurrentMediaTime()
                lock.lock()
                if samples.count < 12_000 { samples.append((t, frames)) }
                lock.unlock()
                usleep(2000)
            }
            lock.lock()
            let all = samples, cuts = marks, from = started, name = label
            samples = []
            lock.unlock()
            UITestTrace.log(Self.summary(name, samples: all, marks: cuts, start: from))
        }

        // MARK: Summary

        private struct Frame: Hashable {
            let image: String
            let symbol: String
            var isApp: Bool { image.hasPrefix("CatchWords") }
            var line: String { "\(image)  \(symbol)" }
        }

        private static func summary(_ label: String, samples: [(t: CFTimeInterval, frames: [UInt])],
                                    marks: [(t: CFTimeInterval, name: String)], start: CFTimeInterval) -> String {
            var names: [UInt: Frame] = [:]
            func frame(_ addr: UInt, leaf: Bool) -> Frame {
                if let f = names[addr] { return f }
                var info = Dl_info()
                let look = leaf ? addr : addr &- 1
                var f = Frame(image: "?", symbol: String(format: "0x%lx", addr))
                if dladdr(UnsafeRawPointer(bitPattern: look), &info) != 0 {
                    let image = info.dli_fname.map { (String(cString: $0) as NSString).lastPathComponent } ?? "?"
                    let sym = info.dli_sname.map { MainStackSampler.demangled(String(cString: $0)) } ?? "?"
                    f = Frame(image: image, symbol: String(sym.prefix(170)))
                }
                names[addr] = f
                return f
            }
            // A sample whose innermost frames wait for the next event: the main thread was free.
            func idle(_ frames: [Frame]) -> Bool {
                frames.prefix(4).contains { $0.symbol.contains("mach_msg") }
            }
            let named: [(t: CFTimeInterval, frames: [Frame])] = samples.map { s in
                (s.t, s.frames.enumerated().map { frame($0.element, leaf: $0.offset == 0) })
            }
            var out = "profile \(label): \(samples.count) samples over \(Int(((samples.last?.t ?? start) - start) * 1000)) ms"
            out += ", marks " + marks.map { "\($0.name) +\(Int(($0.t - start) * 1000))" }.joined(separator: " ")
            // The parts: begin → first mark → … → last mark, and the second after the impact apart.
            var bounds: [(name: String, from: CFTimeInterval, to: CFTimeInterval)] = []
            var cut = [(t: start, name: "begin")] + marks
            cut.append((samples.last?.t ?? start, "end"))
            for i in 0..<(cut.count - 1) where cut[i + 1].t > cut[i].t {
                bounds.append(("\(cut[i].name)→\(cut[i + 1].name)", cut[i].t, cut[i + 1].t))
            }
            if let hit = marks.first(where: { $0.name == "impact" }) {
                bounds.append(("impact+1s", hit.t, hit.t + 1))
            }
            bounds.append(("all", start, .infinity))
            for part in bounds {
                let these = named.filter { $0.t >= part.from && $0.t < part.to }
                guard !these.isEmpty else { continue }
                let busy = these.filter { !idle($0.frames) }
                out += "\n  [\(part.name)] \(these.count) samples, main busy \(Int(Double(busy.count) * 100 / Double(these.count)))%"
                // The longest stretch the main thread was busy without a break (the picture frozen that long).
                var best: (from: Int, to: Int) = (0, -1)
                var bestLength: CFTimeInterval = -1
                var runFrom = -1
                for i in these.indices {
                    if idle(these[i].frames) { runFrom = -1; continue }
                    if runFrom < 0 { runFrom = i }
                    let length = these[i].t - these[runFrom].t
                    if length > bestLength {
                        bestLength = length
                        best = (runFrom, i)
                    }
                }
                if best.to >= best.from {
                    let ms = Int((these[best.to].t - these[best.from].t) * 1000)
                    out += "; longest busy \(ms) ms at +\(Int((these[best.from].t - start) * 1000))"
                    let stretch = Array(these[best.from...best.to])
                    out += "\n    in that stretch:" + top(stretch, limit: 18)
                }
                if !busy.isEmpty {
                    out += "\n    all busy samples:" + top(busy, limit: 30)
                }
            }
            return out
        }

        /// Each function's share of the samples it is on the stack in (once per sample), the app's own first.
        private static func top(_ samples: [(t: CFTimeInterval, frames: [Frame])], limit: Int) -> String {
            var inclusive: [Frame: Int] = [:]
            var leaf: [Frame: Int] = [:]
            for s in samples {
                for f in Set(s.frames) { inclusive[f, default: 0] += 1 }
                if let first = s.frames.first { leaf[first, default: 0] += 1 }
            }
            let n = Double(max(1, samples.count))
            func pct(_ c: Int) -> String { String(format: "%3.0f%%", Double(c) * 100 / n) }
            // Below the run loop's own frames (always on the stack): what the app and the frameworks did.
            let common = inclusive.filter { Double($0.value) >= n * 0.97 }
            var lines = ""
            let app = inclusive.filter { $0.key.isApp && common[$0.key] == nil }.sorted { $0.value > $1.value }.prefix(limit)
            lines += "\n      app (inclusive):"
            for (f, c) in app { lines += "\n        \(pct(c)) \(f.symbol)" }
            let system = inclusive.filter { !$0.key.isApp && common[$0.key] == nil }.sorted { $0.value > $1.value }.prefix(limit)
            lines += "\n      frameworks (inclusive):"
            for (f, c) in system { lines += "\n        \(pct(c)) \(f.line)" }
            lines += "\n      innermost:"
            for (f, c) in leaf.sorted(by: { $0.value > $1.value }).prefix(12) { lines += "\n        \(pct(c)) \(f.line)" }
            return lines
        }
    }
}
#else
/// Release builds: nothing is measured.
nonisolated enum MainProfiler {
    static func begin(_ label: String) {}
    static func mark(_ name: String) {}
    static func end() {}
}
#endif
