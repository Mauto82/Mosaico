import CoreGraphics

/// Posting of synthetic mouse/keyboard events (to drive Mission Control:
/// a desktop switch shortcut and window transport with a simulated drag).
enum EventPoster {
    struct KeyboardShortcut {
        let keyCode: CGKeyCode
        let flags: CGEventFlags

        init?(keyEquivalent: UInt16, keyCode: UInt16, modifiers: UInt32) {
            // WindowServer can report an enabled shortcut with no assigned key.
            guard keyCode != .max, keyCode != 0 || keyEquivalent != .max else { return nil }
            self.keyCode = keyCode
            self.flags = CGEventFlags(rawValue: UInt64(modifiers))
        }
    }

    private static let windowDragTag: Int64 = 0x4D6F736169636F

    static func isWindowDragEvent(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == windowDragTag
    }

    static func windowDragEvent(_ type: CGEventType, at point: CGPoint) -> CGEvent? {
        guard let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else { return nil }
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: windowDragTag)
        event.setIntegerValueField(.mouseEventClickState, value: type == .mouseMoved ? 0 : 1)
        return event
    }

    static func postShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false) else { return false }
        for event in [down, up] {
            event.flags = shortcut.flags
            event.post(tap: .cghidEventTap)
        }
        return true
    }
}
