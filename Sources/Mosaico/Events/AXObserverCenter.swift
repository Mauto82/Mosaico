import AppKit
import ApplicationServices

/// One AXObserver per app; all notifications converge on the main run loop
/// and are forwarded to the WindowManager.
///
/// Destruction is watched on each managed WINDOW, never on the app element:
/// registered there, the app reports the death of every element it has —
/// web content, table cells, menu items. Scrolling a page in Safari or a
/// Chromium app destroys elements by the thousand, each one a message to us
/// and a window-list query to the window server: scrolling and Space
/// switches stuttered system-wide while Mosaico ran.
final class AXObserverCenter {
    static let appNotifications: [String] = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    private var observers: [pid_t: AXObserver] = [:]

    /// Windows whose destruction is watched, with the element it was registered on.
    private var watchedWindows: [WindowID: (pid: pid_t, element: AXUIElement)] = [:]

    var onEvent: ((_ pid: pid_t, _ notification: String, _ element: AXUIElement) -> Void)?

    func observe(pid: pid_t) {
        guard observers[pid] == nil else { return }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let center = Unmanaged<AXObserverCenter>.fromOpaque(refcon).takeUnretainedValue()
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            center.onEvent?(pid, notification as String, element)
        }

        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let appElement = AXUIElementCreateApplication(pid)
        for name in Self.appNotifications {
            AXObserverAddNotification(observer, appElement, name as CFString, refcon)
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    /// Watches the window's destruction. Idempotent; a new element for the
    /// same window (a healed handle) replaces the old registration.
    func watchDestruction(of window: AXWindow) {
        guard let observer = observers[window.pid] else { return }
        if let current = watchedWindows[window.id], CFEqual(current.element, window.element) { return }
        unwatchDestruction(of: window.id)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let err = AXObserverAddNotification(observer, window.element,
                                            kAXUIElementDestroyedNotification as CFString, refcon)
        // A failed registration (app busy, window on another Space) is
        // retried by the next sync instead of being recorded as watched
        guard err == .success || err == .notificationAlreadyRegistered else { return }
        watchedWindows[window.id] = (window.pid, window.element)
    }

    func unwatchDestruction(of id: WindowID) {
        guard let watched = watchedWindows.removeValue(forKey: id),
              let observer = observers[watched.pid] else { return }
        AXObserverRemoveNotification(observer, watched.element, kAXUIElementDestroyedNotification as CFString)
    }

    /// Drops the watches of windows no longer managed.
    func keepWatching(only ids: Set<WindowID>) {
        for id in watchedWindows.keys where !ids.contains(id) {
            unwatchDestruction(of: id)
        }
    }

    func stopObserving(pid: pid_t) {
        watchedWindows = watchedWindows.filter { $0.value.pid != pid }
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    func stopAll() {
        for pid in Array(observers.keys) {
            stopObserving(pid: pid)
        }
    }
}
