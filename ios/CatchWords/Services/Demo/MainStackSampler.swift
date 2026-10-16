#if DEBUG
import Darwin
import Foundation

/// The main thread's call stack, read from another thread while the main thread does not answer (UI tests only, through
/// `UITestTrace`'s watchdog): a stall in the tour's trace then says which code held the main thread, not only how long.
/// The main thread is paused for the few microseconds the return addresses take to copy (frame-pointer walk, inside
/// its own stack only, nothing allocated while it is paused), then the addresses are named with `dladdr` — the app's
/// development build keeps its symbols — and Swift names are demangled.
nonisolated enum MainStackSampler {
    nonisolated(unsafe) private static var mainThread: thread_act_t = 0
    nonisolated(unsafe) private static var stackLow: UInt = 0
    nonisolated(unsafe) private static var stackHigh: UInt = 0

    /// Remembers the main thread. Called once, on the main thread.
    static func captureMain() {
        guard pthread_main_np() != 0 else { return }
        mainThread = mach_thread_self()
        let me = pthread_self()
        let top = UInt(bitPattern: pthread_get_stackaddr_np(me))
        let size = UInt(pthread_get_stacksize_np(me))
        stackHigh = top
        stackLow = top > size ? top - size : 0
    }

    /// The main thread's return addresses, innermost first (empty when it cannot be read).
    static func sample(maxFrames: Int = 64) -> [UInt] {
        #if arch(arm64)
        guard mainThread != 0 else { return [] }
        // Everything is allocated before the thread is paused: it may hold the allocator's lock.
        var frames = [UInt](repeating: 0, count: maxFrames)
        // arm_thread_state64_t: x0…x28, fp, lr, sp, pc, cpsr + pad (34 × 64 bits).
        var regs = [UInt64](repeating: 0, count: 34)
        var n = 0
        let low = stackLow, high = stackHigh
        guard thread_suspend(mainThread) == KERN_SUCCESS else { return [] }
        frames.withUnsafeMutableBufferPointer { out in
            regs.withUnsafeMutableBufferPointer { r in
                guard let base = r.baseAddress else { return }
                var count = mach_msg_type_number_t(34 * 2)
                let kr = base.withMemoryRebound(to: natural_t.self, capacity: 68) {
                    thread_get_state(mainThread, thread_state_flavor_t(ARM_THREAD_STATE64), $0, &count)
                }
                guard kr == KERN_SUCCESS else { return }
                out[0] = UInt(r[32]); n = 1               // pc
                out[1] = UInt(r[30]); n = 2               // lr
                var fp = UInt(r[29])
                while n < out.count, fp & 7 == 0, fp >= low, fp + 16 <= high {
                    guard let frame = UnsafePointer<UInt>(bitPattern: fp) else { break }
                    let next = frame[0]
                    let ret = frame[1]
                    if ret == 0 { break }
                    out[n] = ret
                    n += 1
                    if next <= fp { break }
                    fp = next
                }
            }
        }
        thread_resume(mainThread)
        return Array(frames.prefix(n))
        #else
        return []
        #endif
    }

    /// One line per frame: `image  symbol + offset`. Runs of frames from the same system library are folded into one
    /// line, so the app's own frames stand out.
    static func describe(_ frames: [UInt], limit: Int = 40) -> [String] {
        var lines: [String] = []
        var folded: (image: String, count: Int)?
        func flush() {
            if let f = folded, f.count > 0 { lines.append("… \(f.count) more in \(f.image)") }
            folded = nil
        }
        for (i, addr) in frames.prefix(limit).enumerated() {
            // A return address points after the call: look up the call itself.
            let look = i == 0 ? addr : addr &- 1
            var info = Dl_info()
            guard dladdr(UnsafeRawPointer(bitPattern: look), &info) != 0 else {
                flush()
                lines.append(String(format: "0x%lx", addr))
                continue
            }
            let image = info.dli_fname.map { (String(cString: $0) as NSString).lastPathComponent } ?? "?"
            let isApp = image.hasPrefix("CatchWords")
            let name = info.dli_sname.map { demangle(String(cString: $0)) } ?? "?"
            let offset = info.dli_saddr.map { Int(bitPattern: look) - Int(bitPattern: $0) } ?? 0
            if !isApp, let f = folded, f.image == image {
                folded = (image, f.count + 1)
                continue
            }
            flush()
            lines.append("\(image)  \(name.prefix(220)) + \(offset)")
            if !isApp { folded = (image, 0) }
        }
        flush()
        return lines
    }

    private typealias Demangle = @convention(c) (UnsafePointer<CChar>?, Int, UnsafeMutablePointer<CChar>?,
                                                  UnsafeMutablePointer<Int>?, UInt32) -> UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) private static let swiftDemangle: Demangle? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swift_demangle") else { return nil }   // RTLD_DEFAULT
        return unsafeBitCast(sym, to: Demangle.self)
    }()

    private static func demangle(_ name: String) -> String {
        guard let fn = swiftDemangle, name.hasPrefix("$s") || name.hasPrefix("_$s") else { return name }
        let raw = name.hasPrefix("_") ? String(name.dropFirst()) : name
        return raw.withCString { c in
            guard let out = fn(c, strlen(c), nil, nil, 0) else { return name }
            defer { free(out) }
            return String(cString: out)
        }
    }
}
#endif
