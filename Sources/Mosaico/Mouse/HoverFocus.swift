import AppKit

/// Passive mouse observation and dwell timing. All state is used on the main thread.
final class HoverFocus {
    struct Target: Equatable {
        let id: WindowID
        let pid: pid_t
    }

    struct Dwell {
        static let delay: TimeInterval = 0.15
        private var target: Target?
        private var began: TimeInterval = 0
        private var attempted = false
        private var blockedTarget: Target?

        init(blocking target: Target? = nil) {
            blockedTarget = target
        }

        mutating func cancelPending() {
            self = Dwell(blocking: blockedTarget)
        }

        mutating func observe(_ hit: Target?, at now: TimeInterval) -> Target? {
            if let blockedTarget, blockedTarget == hit { return nil }
            blockedTarget = nil
            if hit != target {
                target = hit
                began = now
                attempted = false
            }
            guard let target, !attempted, now >= began + Self.delay else { return nil }
            attempted = true
            return target
        }

        var deadline: TimeInterval? {
            target != nil && !attempted ? began + Self.delay : nil
        }
    }

    var hitTest: ((CGPoint) -> Target?)?
    var focus: ((Target) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var work: DispatchWorkItem?
    private var dwell = Dwell()
    private var suspendedUntil: TimeInterval = 0
    private static let sampleInterval: TimeInterval = 0.04

    private var inputAllowsHover: Bool {
        NSEvent.pressedMouseButtons == 0 && !NSEvent.modifierFlags.contains(.option)
    }

    static var pointer: CGPoint {
        let location = NSEvent.mouseLocation
        return DisplayManager.axRect(fromCocoa: CGRect(origin: location, size: .zero)).origin
    }

    func start() {
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown,
                                           .otherMouseDown, .scrollWheel, .flagsChanged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.observe(event)
        }
        if globalMonitor == nil {
            MosaicoLog.log("hover focus: could not install mouse monitor")
            return
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.cancel()
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        suspendedUntil = 0
        cancel()
    }

    func cancel() {
        cancelDwell()
        dwell = Dwell()
    }

    private func cancelDwell() {
        work?.cancel()
        work = nil
        dwell.cancelPending()
    }

    func suspend(for duration: TimeInterval) {
        cancel()
        suspendedUntil = max(suspendedUntil, ProcessInfo.processInfo.systemUptime + duration)
    }

    func explicitFocus() {
        cancel()
        if globalMonitor != nil { dwell = Dwell(blocking: hitTest?(Self.pointer)) }
    }

    private func observe(_ event: NSEvent) {
        if event.type == .flagsChanged {
            if !inputAllowsHover { cancelDwell() }
            return
        }
        guard event.type == .mouseMoved,
              event.cgEvent.map({ !EventPoster.isWindowDragEvent($0) }) ?? true else {
            cancel()
            return
        }
        guard inputAllowsHover, ProcessInfo.processInfo.systemUptime >= suspendedUntil else { return }
        if work == nil { schedule(after: Self.sampleInterval) }
    }

    private func schedule(after delay: TimeInterval) {
        let item = DispatchWorkItem { [weak self] in self?.sample() }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func sample() {
        work = nil
        guard inputAllowsHover else {
            cancelDwell()
            return
        }
        let hit = hitTest?(Self.pointer)
        let now = ProcessInfo.processInfo.systemUptime
        if let target = dwell.observe(hit, at: now) {
            focus?(target)
        } else if let deadline = dwell.deadline {
            schedule(after: min(Self.sampleInterval, max(0, deadline - now)))
        }
    }
}
