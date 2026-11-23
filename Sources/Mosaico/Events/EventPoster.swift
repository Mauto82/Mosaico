import CoreGraphics
import Carbon.HIToolbox

/// Posting of synthetic mouse/keyboard events (to drive Mission Control:
/// space switching via Ctrl+N and window transport with a simulated drag).
enum EventPoster {
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

    /// Ctrl + key (keycode) — keyDown and keyUp.
    static func postCtrlKey(_ keyCode: CGKeyCode) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return false }
        for event in [down, up] {
            event.flags = .maskControl
            event.post(tap: .cghidEventTap)
        }
        return true
    }

    /// Keycode of digit 1..9 (top row).
    static func digitKeyCode(_ digit: Int) -> CGKeyCode? {
        let codes: [Int: Int] = [
            1: kVK_ANSI_1, 2: kVK_ANSI_2, 3: kVK_ANSI_3, 4: kVK_ANSI_4,
            5: kVK_ANSI_5, 6: kVK_ANSI_6, 7: kVK_ANSI_7, 8: kVK_ANSI_8, 9: kVK_ANSI_9,
        ]
        guard let code = codes[digit] else { return nil }
        return CGKeyCode(code)
    }
}
