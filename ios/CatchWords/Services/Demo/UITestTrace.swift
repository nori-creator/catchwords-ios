import UIKit

/// The UI tests' trace (DEBUG builds launched with `-uiDemo` only; a no-op everywhere else): one line per touch the
/// app's windows receive and per step of the catch, in the app's caches (`uitest-trace.txt`). CI publishes it next
/// to the tour's screenshots, so a tap that did nothing on CI can be followed after the fact — where the touch
/// landed, which gestures took it, and what the words screen did with it.
nonisolated enum UITestTrace {
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard DemoBackend.isOn else { return }
        Writer.shared.append(message())
        #endif
    }

    #if DEBUG
    /// When `start()` ran (the app's launch), for the timing lines (`once`).
    nonisolated(unsafe) private static var launchedAt = Date()
    nonisolated(unsafe) private static var timed: Set<String> = []
    private static let timedLock = NSLock()
    #endif

    /// Logs "+2.41 s <event>" the first time `event` happens after launch (the first photo on screen, the dex read):
    /// how long a launch takes to show what matters, compared run to run.
    static func once(_ event: String, _ detail: @autoclosure () -> String = "") {
        #if DEBUG
        guard DemoBackend.isOn else { return }
        timedLock.lock()
        let first = timed.insert(event).inserted
        timedLock.unlock()
        guard first else { return }
        let more = detail()
        log(String(format: "+%.2f s ", Date().timeIntervalSince(launchedAt)) + event + (more.isEmpty ? "" : " " + more))
        #endif
    }

    /// At launch: a header naming the run, and the touch log.
    @MainActor
    static func start() {
        #if DEBUG
        guard DemoBackend.isOn else { return }
        launchedAt = Date()
        let d = UserDefaults.standard
        // The pid: an XCUITest failure names the process it could not read (kAXErrorIPCTimeout "for <pid>", tour
        // 2026-10-15), so it can be told whether that was this app or a process of the simulator.
        log("launch uiDemo=\(d.string(forKey: "uiDemo") ?? "-") lang=\(d.string(forKey: "ui.lang") ?? "-") pid=\(getpid())")
        UIWindow.traceTouches()
        MainStackSampler.captureMain()
        MainWatchdog.shared.start()
        #endif
    }

    #if DEBUG
    /// Logs every time the main thread does not answer for more than a second, and when it answers again: an
    /// accessibility query that times out during the tour can then be laid against what the app's main thread did.
    /// While it does not answer, its call stack is logged every 2 seconds (`MainStackSampler`): what held it.
    nonisolated private final class MainWatchdog: @unchecked Sendable {
        static let shared = MainWatchdog()
        private let queue = DispatchQueue(label: "app.catchwords.uitest-watchdog")
        private let lock = NSLock()
        private var beat = Date()
        private var stalledSince: Date?
        private var sampledAt: Date?
        private var timer: DispatchSourceTimer?

        func start() {
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 1, repeating: 0.5)
            t.setEventHandler { [self] in check() }
            timer = t
            t.resume()
        }

        private func check() {
            let now = Date()
            lock.lock()
            let gap = now.timeIntervalSince(beat)
            let first = gap > 1 && stalledSince == nil
            if first { stalledSince = beat }
            lock.unlock()
            if first { UITestTrace.log("main thread not answering for \(String(format: "%.1f", gap)) s") }
            // Only this queue reads and writes `sampledAt`.
            if gap <= 1 { sampledAt = nil }
            if gap > 1, sampledAt.map({ now.timeIntervalSince($0) >= 2 }) ?? true {
                sampledAt = now
                let lines = MainStackSampler.describe(MainStackSampler.sample())
                UITestTrace.log("main stack after \(String(format: "%.1f", gap)) s:\n    " + lines.joined(separator: "\n    "))
            }
            DispatchQueue.main.async { [self] in
                let back = Date()
                lock.lock()
                let since = stalledSince
                beat = back
                stalledSince = nil
                lock.unlock()
                if let since {
                    UITestTrace.log("main thread answering again after \(String(format: "%.1f", back.timeIntervalSince(since))) s")
                }
            }
        }
    }
    #endif

    #if DEBUG
    /// Appends off the main thread, in order.
    nonisolated private final class Writer: @unchecked Sendable {
        static let shared = Writer()
        private let queue = DispatchQueue(label: "app.catchwords.uitest-trace")
        private let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("uitest-trace.txt")
        private let clock: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "HH:mm:ss.SSS"
            return f
        }()

        func append(_ message: String) {
            let now = Date()
            queue.async { [self] in
                let line = clock.string(from: now) + " " + message + "\n"
                guard let data = line.data(using: .utf8) else { return }
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                } else {
                    try? data.write(to: url)
                }
            }
        }
    }
    #endif
}

#if DEBUG
extension UIWindow {
    /// Every window's `sendEvent` logs its touches as they begin and end — before UIKit handles them (where the touch
    /// landed) and after (what each gesture recognizer made of it). Only reads; the event goes on unchanged.
    static func traceTouches() {
        guard let original = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.sendEvent(_:))),
              let traced = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.cw_traceSendEvent(_:))) else { return }
        method_exchangeImplementations(original, traced)
    }

    /// `dynamic`: the call inside goes through the runtime, so after the exchange it reaches the original.
    @objc private dynamic func cw_traceSendEvent(_ event: UIEvent) {
        traceTouches(of: event, after: false)
        cw_traceSendEvent(event)   // the original sendEvent (exchanged)
        traceTouches(of: event, after: true)
    }

    private func traceTouches(of event: UIEvent, after: Bool) {
        guard event.type == .touches, let touches = event.allTouches else { return }
        for t in touches {
            let phase: String
            switch t.phase {
            case .began: phase = "began"
            case .ended: phase = "ended"
            case .cancelled: phase = "cancelled"
            default: continue
            }
            // Before: where it landed. After: the recognizers' states (0 possible, 3 recognized, 4 cancelled, 5 failed).
            if !after && t.phase != .began { continue }
            let p = t.location(in: self)
            let view = t.view.map { String(describing: type(of: $0)) } ?? "nil"
            let recognizers = (t.gestureRecognizers ?? []).map { r in
                "\(type(of: r))\(r.name.map { "(\($0))" } ?? "")#\(r.state.rawValue)\(r.isEnabled ? "" : "-off")"
            }
            var line = "touch \(phase)\(after ? " handled" : "") @\(Int(p.x)),\(Int(p.y)) window=\(type(of: self))"
            line += " level=\(Int(windowLevel.rawValue)) key=\(isKeyWindow) view=\(view)"
            line += " recognizers=[\(recognizers.joined(separator: " "))]"
            // As a touch begins: every window of the scene (class:level, h = hidden, n = no touches) and the app's state.
            if t.phase == .began, !after, let ws = windowScene {
                let list = ws.windows.map { w in
                    "\(type(of: w)):\(Int(w.windowLevel.rawValue))\(w.isHidden ? "h" : "")\(w.isUserInteractionEnabled ? "" : "n")"
                }
                line += " windows=[\(list.joined(separator: " "))] app=\(UIApplication.shared.applicationState.rawValue)"
            }
            UITestTrace.log(line)
        }
    }
}
#endif
