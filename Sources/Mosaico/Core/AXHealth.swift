import AppKit
import ApplicationServices

/// Backs off apps that do not answer Accessibility.
///
/// An AX call blocks until the target app answers or the messaging timeout
/// (0.5s) expires. An app that never answers — Windows App while it holds a
/// remote session, typically — cost that half second on every frame read,
/// every validity check and every set, dozens of times per pass: right after
/// each Space switch Mosaico froze for 2–5 seconds. A call that fails after
/// running out the clock now puts the app on a back-off (a slow call that
/// succeeds does not: a big window can take a while to resize). For a
/// while every AX call to it fails at once, without IPC. The first call
/// after the back-off tests it again: an answer clears it, another timeout
/// lengthens the wait (up to two minutes).
///
/// Thread-safe: the mouse thread moves windows during an ⌥-drag.
enum AXHealth {
    /// A failed call this slow ran out the messaging timeout.
    static let slowCall: TimeInterval = 0.3
    static let backOffSteps: [TimeInterval] = [10, 30, 60, 120]

    private struct State {
        var until: Date
        var step: Int
    }

    private static let lock = NSLock()
    private static var states: [pid_t: State] = [:]

    /// True while the app is backed off: callers treat it as not answering.
    static func isBackedOff(_ pid: pid_t) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let state = states[pid] else { return false }
        return Date() < state.until
    }

    /// Runs one AX call against the app, unless it is backed off (then the
    /// call is skipped and reported as `.cannotComplete`, like a timeout).
    @discardableResult
    static func call(_ pid: pid_t, _ body: () -> AXError) -> AXError {
        if isBackedOff(pid) { return .cannotComplete }
        let started = Date()
        let err = body()
        record(pid, timedOut: err == .cannotComplete && Date().timeIntervalSince(started) >= slowCall,
               elapsed: Date().timeIntervalSince(started))
        return err
    }

    private static func record(_ pid: pid_t, timedOut: Bool, elapsed: TimeInterval) {
        lock.lock()
        let previous = states[pid]
        guard timedOut else {
            // An answer: forget any past back-off
            if previous != nil { states[pid] = nil }
            lock.unlock()
            return
        }
        // A slow call that raced a back-off another call already started
        if let previous, Date() < previous.until {
            lock.unlock()
            return
        }
        let step = previous.map { min($0.step + 1, backOffSteps.count - 1) } ?? 0
        let duration = backOffSteps[step]
        states[pid] = State(until: Date().addingTimeInterval(duration), step: step)
        lock.unlock()

        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
        MosaicoLog.log(String(format: "AX back-off: %@ timed out after %.0fms — skipped for %.0fs",
                              name, elapsed * 1000, duration))
    }

    /// The app quit: its pid may be reused.
    static func forget(_ pid: pid_t) {
        lock.lock(); states[pid] = nil; lock.unlock()
    }
}
