import AppKit

/// Applies the frames computed by the BSPTree to the real windows.
enum LayoutEngine {

    /// Windows that refused their last target (a minimum size, typically:
    /// WhatsApp, Claude, OBS), with the frame they kept. Asking again for
    /// the same target is wasted work for nothing — every attempt makes the
    /// app re-lay out its content, and Electron apps pay seconds of CPU for
    /// it — so the request is repeated only when the target or the window
    /// itself changes. Main thread only.
    private static var refusals: [WindowID: (target: CGRect, kept: CGRect)] = [:]

    /// Frame a window kept after refusing its slot, if it did: the hit-test
    /// must look for it there, not in the slot.
    static func refusedFrame(of id: WindowID) -> CGRect? {
        refusals[id]?.kept
    }

    /// True if the window already refused exactly this target and has not
    /// moved since.
    private static func alreadyRefused(_ managed: ManagedWindow, _ target: CGRect, current: CGRect) -> Bool {
        guard let refusal = refusals[managed.id] else { return false }
        return rectsEqual(refusal.target, target) && rectsEqual(refusal.kept, current)
    }

    /// Usable workspace rect: visibleFrame − padding.
    static func workspaceRect(for screen: NSScreen) -> CGRect {
        let padding = CGFloat(SettingsStore.shared.settings.padding)
        return DisplayManager.axVisibleFrame(of: screen).insetBy(dx: padding, dy: padding)
    }

    /// Default float frame: grid 4:4:1:1:2:2 (centered, half width/height).
    static func floatFrame(for screen: NSScreen) -> CGRect {
        let rect = workspaceRect(for: screen)
        return CGRect(x: rect.origin.x + rect.width / 4,
                      y: rect.origin.y + rect.height / 4,
                      width: rect.width / 2,
                      height: rect.height / 2)
    }

    /// Applies the workspace layout on the display. Temporarily disables
    /// AXEnhancedUserInterface for the apps involved (animation bug), then a
    /// delayed re-apply for the windows that did not comply.
    static func apply(workspace: Workspace, on screen: NSScreen) {
        let rect = workspaceRect(for: screen)
        let gap = CGFloat(SettingsStore.shared.settings.gap)
        let frames = workspace.tree.frames(in: rect, gap: gap)

        workspace.layoutGeneration += 1
        let generation = workspace.layoutGeneration

        var byPid: [pid_t: [(ManagedWindow, CGRect)]] = [:]
        for (id, frame) in frames {
            guard let managed = workspace.windows[id], !managed.isFloating else { continue }
            let target = managed.isZoomed ? rect : frame
            byPid[managed.window.pid, default: []].append((managed, target))
        }

        let started = Date()
        var changed = 0
        for (pid, entries) in byPid {
            // Backed off (see AXHealth): every read would come back empty
            // and every write would be dropped — leave its windows be
            guard !AXHealth.isBackedOff(pid) else { continue }
            // Read every frame first: an app whose windows are all in place
            // (or all refused this same target) gets no write at all
            let pending = entries.filter { managed, target in
                let current = managed.window.frame
                return !rectsEqual(current, target) && !alreadyRefused(managed, target, current: current)
            }
            guard !pending.isEmpty else { continue }

            let app = AXApplication(pid: pid)
            let hadEnhanced = app.enhancedUserInterface
            if hadEnhanced { app.enhancedUserInterface = false }

            for (managed, target) in pending {
                managed.window.setFrame(target)
                changed += 1
            }

            if hadEnhanced { app.enhancedUserInterface = true }
        }
        // Duration in the log: a slow pass means an app is not answering
        // Accessibility, which is what a "freeze" looks like from here
        let elapsed = Date().timeIntervalSince(started)
        if changed > 0 || elapsed > 0.25 {
            MosaicoLog.log(String(format: "apply gen=%d set=%d (%.0fms)", generation, changed, elapsed * 1000))
        }

        // Floats (dialogs, fixed-size windows) stay ABOVE the tiled ones —
        // otherwise they disappear behind the tiling that covers the whole
        // screen (i3-style behavior)
        for (_, managed) in workspace.windows where managed.isFloating {
            managed.window.raise()
        }

        // Re-apply for apps slow to apply the frame (only once, 0.1s later).
        // Does NOT adopt the real frame: if the app snaps to a different
        // size (terminals on a cell grid), it is tolerated — chasing it
        // would create an apply→snap→adopt loop. Resize adoption happens
        // only on user action (handleDragEnd).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard workspace.layoutGeneration == generation,
                  NSEvent.pressedMouseButtons == 0 else { return }
            for (pid, entries) in byPid where !AXHealth.isBackedOff(pid) {
                for (managed, target) in entries {
                    let current = managed.window.frame
                    guard !rectsEqual(current, target) else {
                        refusals[managed.id] = nil
                        continue
                    }
                    guard !alreadyRefused(managed, target, current: current) else { continue }
                    managed.window.setFrame(target)
                    // A window that still refuses its frame is the classic
                    // source of "one window covers the others": leave the
                    // evidence in the log, once, and stop asking.
                    let kept = managed.window.frame
                    if !rectsEqual(kept, target, tolerance: 10) {
                        refusals[managed.id] = (target, kept)
                        MosaicoLog.log("stubborn [\(managed.id)] keeps \(kept), wants \(target) — not asking again")
                    } else {
                        refusals[managed.id] = nil
                    }
                }
            }
        }
    }

    static func rectsEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.origin.x - b.origin.x) <= tolerance &&
        abs(a.origin.y - b.origin.y) <= tolerance &&
        abs(a.width - b.width) <= tolerance &&
        abs(a.height - b.height) <= tolerance
    }
}
