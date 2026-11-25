import Foundation
import QuartzCore

/// Every time the main thread is held for longer than a few frames, in the UI tests' trace (`UITestTrace`, DEBUG builds
/// launched with `-uiDemo` only — nothing runs and nothing is allocated anywhere else): `stall <ms>ms`, written when
/// the main thread answers again, so it stands in order between the flow's own trace lines (`openTyped begin`,
/// `choose shown` …), followed by the app's own frames of the main thread's call stack as it was 80 ms into the stall
/// (and again 320 ms into a long one).
/// The CI's `tour` job prints the longest ones to its log (owner 2026-11-25: 「可能な限りアニメーションを滑らかにして、
/// また止まらないようにして」 — the freezes were guessed at from a screen recording; now they are measured).
///
/// How: a timer on its own queue asks the main thread, about 60 times a second, to answer (`DispatchQueue.main.async`)
/// and notes how long the answer took. `MainWatchdog` (UITestTrace.swift) does the same for stalls over a second.
nonisolated enum MainStallMonitor {
    /// A stall is written from this long on (five frames at 60 fps).
    static let threshold = 0.08
    /// The first line of a stall's stack when the main thread was answering the UI test, not doing the app's work.
    static let harnessMark = "(the UI test reading the screen)"

    /// Called once at launch, on the main thread, after `MainStackSampler.captureMain()`.
    static func start() {
        #if DEBUG
        guard DemoBackend.isOn else { return }
        Probe.shared.start()
        #endif
    }

    #if DEBUG
    nonisolated private final class Probe: @unchecked Sendable {
        static let shared = Probe()
        private let queue = DispatchQueue(label: "app.catchwords.uitest-stall", qos: .userInteractive)
        private let lock = NSLock()
        private var timer: DispatchSourceTimer?
        /// When the question the main thread has not answered yet was asked (nil: it has answered). Under `lock`.
        private var askedAt: CFTimeInterval?
        /// The main thread's stack, read while it was not answering (the app's frames, innermost first). Under `lock`.
        private var held: [String] = []
        /// Only `queue` reads and writes these.
        private var lastTick: CFTimeInterval = 0
        private var samples = 0
        /// This process itself was not running (the timer's own ticks stopped: the app was suspended, or the machine
        /// was busy): a late answer then says nothing about the main thread. Under `lock`.
        private var starved = false

        func start() {
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 0.5, repeating: .milliseconds(16), leeway: .milliseconds(2))
            t.setEventHandler { [self] in tick() }
            timer = t
            t.resume()
        }

        private func tick() {
            let now = CACurrentMediaTime()
            let gap = lastTick > 0 ? now - lastTick : 0
            lastTick = now
            lock.lock()
            if gap > 0.1 { starved = true }
            guard let asked = askedAt else {
                // The main thread has answered the last question: ask again.
                askedAt = now
                starved = false
                held = []
                lock.unlock()
                samples = 0
                DispatchQueue.main.async { [self] in answered(asked: now) }
                return
            }
            lock.unlock()
            // Still not answered after `threshold`: what the main thread is doing, read then and once more in a long stall.
            let waited = now - asked
            guard samples < Self.sampleAt.count, waited >= Self.sampleAt[samples] else { return }
            samples += 1
            var lines = Self.appFrames(MainStackSampler.describe(MainStackSampler.sample(maxFrames: 160), limit: 160))
            guard !lines.isEmpty else { return }
            lines.insert("after \(Int((waited * 1000).rounded())) ms:", at: 0)
            lock.lock()
            if askedAt == asked { held += lines }
            lock.unlock()
        }

        /// On the main thread: it took `late` to get here.
        private func answered(asked: CFTimeInterval) {
            let late = CACurrentMediaTime() - asked
            lock.lock()
            let stack = held
            let skip = starved
            askedAt = nil
            held = []
            lock.unlock()
            guard late >= MainStallMonitor.threshold, !skip else { return }
            var line = "stall \(Int((late * 1000).rounded()))ms"
            if !stack.isEmpty { line += "\n    " + stack.joined(separator: "\n    ") }
            UITestTrace.log(line)
        }

        /// How long into a stall the main thread's stack is read.
        private static let sampleAt: [Double] = [MainStallMonitor.threshold, 0.32]

        /// The innermost frames (what the thread was in) and the app's own frames under them (who asked for it).
        private static func appFrames(_ lines: [String]) -> [String] {
            var out = Array(lines.prefix(3))
            // The UI test reads the screen on the app's main thread (its accessibility queries): said so, so that the
            // CI's summary does not take those for the app's own work.
            if lines.contains(where: { $0.contains("XCTAutomationSupport") }) { out.insert(MainStallMonitor.harnessMark, at: 0) }
            for l in lines.dropFirst(3) where l.hasPrefix("CatchWords") {
                out.append(l)
                if out.count >= 14 { break }
            }
            return out
        }
    }
    #endif
}
