import AppKit

/// Carries a window through a Mission Control shortcut on the main queue.
/// The workspace model stays frozen until the synthetic button is released
/// and the window server has reported the window's resulting membership.
final class NativeSpaceMove {
    enum Outcome: Equatable {
        case moved(NativeSpaceID)
        case stayed
        case unknown
        case cancelled(String)
    }

    struct Verification {
        let source: NativeSpaceID
        let destination: NativeSpaceID
        private var previous: NativeSpaceID?

        init(source: NativeSpaceID, destination: NativeSpaceID) {
            self.source = source
            self.destination = destination
        }

        mutating func observe(_ spaces: [NativeSpaceID], timedOut: Bool) -> Outcome? {
            // A transition can report both Desktops or neither. Wait for
            // two readings in agreement before committing a relocation.
            let space = spaces.count == 1 && spaces[0] != 0 ? spaces[0] : nil
            defer { previous = space }
            if let space, space == previous, space == destination || timedOut && space != source {
                return .moved(space)
            }
            if timedOut { return space == source ? .stayed : .unknown }
            return nil
        }
    }

    var windowID: WindowID { window.id }
    let source: NativeSpaceID
    let destination: NativeSpaceID
    let displayID: CGDirectDisplayID
    private let window: AXWindow
    private let key: CGKeyCode
    private let completion: (Outcome, NativeSpaceID?) -> Void

    private var nextStep: DispatchWorkItem?
    private var mouseUp: CGEvent?
    private var switchDeadline: TimeInterval?
    private var finished = false

    init(window: AXWindow, source: NativeSpaceID, destination: NativeSpaceID,
         displayID: CGDirectDisplayID, key: CGKeyCode,
         completion: @escaping (Outcome, NativeSpaceID?) -> Void) {
        self.window = window
        self.source = source
        self.destination = destination
        self.displayID = displayID
        self.key = key
        self.completion = completion
    }

    private var activeSpace: NativeSpaceID? {
        DisplayManager.screen(withDisplayID: displayID).flatMap { SpaceTracker.currentSpace(for: $0) }
    }

    func start() {
        tryGrab(attempt: 0)
    }

    private func tryGrab(attempt: Int) {
        guard let frame = window.frameIfReadable, NSEvent.pressedMouseButtons == 0, activeSpace == source else {
            finish(.cancelled("source window or mouse unavailable"))
            return
        }
        // Custom browser chrome can put its address bar where a standard
        // title bar would be. Try the thin strip above the toolbar as well.
        let candidates = [
            CGPoint(x: frame.midX, y: frame.minY + 10),
            CGPoint(x: frame.maxX - min(35, frame.width / 4), y: frame.minY + 4),
            CGPoint(x: frame.midX, y: frame.minY + 4)
        ]
        guard candidates.indices.contains(attempt) else {
            finish(.cancelled("could not start a drag from the title bar"))
            return
        }
        let point = candidates[attempt]
        guard !window.isOverControl(at: point) else {
            tryGrab(attempt: attempt + 1)
            return
        }
        guard let position = EventPoster.windowDragEvent(.mouseMoved, at: point) else {
            finish(.cancelled("could not create cursor event"))
            return
        }
        position.post(tap: .cghidEventTap)
        schedule(after: 0.12) { $0.press(at: point, attempt: attempt) }
    }

    func spaceDidChange() {
        if switchDeadline != nil { waitForSwitch() }
    }

    func cancel(reason: String) {
        finish(.cancelled(reason))
    }

    private func press(at point: CGPoint, attempt: Int) {
        guard NSEvent.pressedMouseButtons == 0, activeSpace == source,
              let front = WindowDiscovery.frontWindow(at: point), front.id == windowID else {
            finish(.cancelled("window no longer at grab point or mouse in use"))
            return
        }
        guard !window.isOverControl(at: point) else {
            tryGrab(attempt: attempt + 1)
            return
        }
        guard let down = EventPoster.windowDragEvent(.leftMouseDown, at: point),
              let up = EventPoster.windowDragEvent(.leftMouseUp, at: point) else {
            finish(.cancelled("could not create mouse events"))
            return
        }
        mouseUp = up
        down.post(tap: .cghidEventTap)
        schedule(after: 0.04) {
            $0.drag(from: point, step: 1, attempt: attempt, initialBounds: front.bounds)
        }
    }

    private func drag(from grabPoint: CGPoint, step: Int, attempt: Int, initialBounds: CGRect) {
        let point = CGPoint(x: grabPoint.x + CGFloat(step) * 3, y: grabPoint.y + CGFloat(step) * 2)
        guard let event = EventPoster.windowDragEvent(.leftMouseDragged, at: point) else {
            finish(.cancelled("could not create drag event"))
            return
        }
        mouseUp?.location = point
        event.post(tap: .cghidEventTap)
        if step < 4 {
            schedule(after: 0.03) {
                $0.drag(from: grabPoint, step: step + 1, attempt: attempt, initialBounds: initialBounds)
            }
        } else {
            schedule(after: 0.12) {
                $0.checkGrab(at: grabPoint, attempt: attempt, initialBounds: initialBounds)
            }
        }
    }

    static func didMove(from initial: CGRect, to current: CGRect) -> Bool {
        abs(current.width - initial.width) <= 3 && abs(current.height - initial.height) <= 3
            && hypot(current.minX - initial.minX, current.minY - initial.minY) >= 4
    }

    private func checkGrab(at point: CGPoint, attempt: Int, initialBounds: CGRect) {
        if let actual = WindowDiscovery.onScreenBounds(of: windowID),
           Self.didMove(from: initialBounds, to: actual) {
            MosaicoLog.log("space move [\(windowID)] grabbed at \(point)")
            switchSpace()
        } else {
            releaseMouse()
            schedule(after: 0.08) { $0.tryGrab(attempt: attempt + 1) }
        }
    }

    private func switchSpace() {
        guard activeSpace == source, EventPoster.postCtrlKey(key) else {
            finish(.cancelled("could not send Mission Control shortcut from source Space"))
            return
        }
        switchDeadline = ProcessInfo.processInfo.systemUptime + 1.2
        waitForSwitch()
    }

    private func waitForSwitch() {
        guard let deadline = switchDeadline else { return }
        if let activeSpace, activeSpace != source {
            switchDeadline = nil
            schedule(after: 0.3) { $0.releaseAndVerify() }
        } else if ProcessInfo.processInfo.systemUptime >= deadline {
            switchDeadline = nil
            releaseAndVerify()
        } else {
            schedule(after: 0.08) { $0.waitForSwitch() }
        }
    }

    private func releaseAndVerify() {
        releaseMouse()
        let verification = Verification(source: source, destination: destination)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.65
        schedule(after: 0.08) { $0.verify(verification, deadline: deadline) }
    }

    private func verify(_ verification: Verification, deadline: TimeInterval) {
        var verification = verification
        let timedOut = ProcessInfo.processInfo.systemUptime >= deadline
        if let outcome = verification.observe(SpaceTracker.spaces(of: windowID), timedOut: timedOut) {
            finish(outcome)
        } else {
            schedule(after: 0.08) { $0.verify(verification, deadline: deadline) }
        }
    }

    private func releaseMouse() {
        guard let mouseUp else { return }
        self.mouseUp = nil
        mouseUp.timestamp = DispatchTime.now().uptimeNanoseconds
        mouseUp.post(tap: .cghidEventTap)
    }

    private func finish(_ outcome: Outcome) {
        guard !finished else { return }
        finished = true
        nextStep?.cancel()
        nextStep = nil
        switchDeadline = nil
        releaseMouse()
        completion(outcome, activeSpace)
    }

    private func schedule(after delay: TimeInterval, _ perform: @escaping (NativeSpaceMove) -> Void) {
        nextStep?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.finished else { return }
            perform(self)
        }
        nextStep = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
