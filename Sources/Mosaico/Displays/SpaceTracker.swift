import AppKit
import CAXShim

typealias NativeSpaceID = UInt64

/// Queries macOS native Spaces (Mission Control) via CGS SPI.
enum SpaceTracker {

    /// Native space currently visible on each display.
    /// Key: "Display Identifier" (UUID string, or "Main" on the primary).
    static func activeSpacesByDisplay() -> [String: NativeSpaceID] {
        guard let raw = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue() as? [[String: Any]] else {
            return [:]
        }
        return activeSpaces(in: raw)
    }

    private static func activeSpaces(in displays: [[String: Any]]) -> [String: NativeSpaceID] {
        var result: [String: NativeSpaceID] = [:]
        for display in displays {
            guard let identifier = display["Display Identifier"] as? String,
                  let current = display["Current Space"] as? [String: Any],
                  let id = (current["id64"] as? NativeSpaceID) ?? (current["ManagedSpaceID"] as? NativeSpaceID) else {
                continue
            }
            result[identifier] = id
        }
        return result
    }

    /// Current native space of the given display.
    static func currentSpace(for screen: NSScreen) -> NativeSpaceID? {
        currentSpace(for: screen, in: activeSpacesByDisplay())
    }

    /// Same, against an already fetched display→space map: one CGS call
    /// serves every display of a pass.
    static func currentSpace(for screen: NSScreen, in spaces: [String: NativeSpaceID]) -> NativeSpaceID? {
        guard !spaces.isEmpty else { return nil }

        let displayID = DisplayManager.displayID(of: screen)
        if let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let uuid = CFUUIDCreateString(nil, cfUUID) as String?,
           let id = spaces[uuid] {
            return id
        }
        // The primary display is sometimes identified as "Main"
        if screen == NSScreen.screens.first, let id = spaces["Main"] {
            return id
        }
        // Only one display: take the single value
        if spaces.count == 1 { return spaces.values.first }
        return nil
    }

    struct Desktops {
        let index: Int
        let ids: [NativeSpaceID]
    }

    static func desktopShortcut(number: Int) -> EventPoster.KeyboardShortcut? {
        // Mission Control's "Switch to Desktop 1" symbolic hotkey ID is 118.
        guard (1...16).contains(number) else { return nil }
        let id = UInt32(117 + number)
        guard CGSIsSymbolicHotKeyEnabled(id) else { return nil }

        var keyEquivalent: UInt16 = 0
        var keyCode: UInt16 = 0
        var modifiers: UInt32 = 0
        guard CGSGetSymbolicHotKeyValue(id, &keyEquivalent, &keyCode, &modifiers) == .success else {
            return nil
        }
        return EventPoster.KeyboardShortcut(keyEquivalent: keyEquivalent, keyCode: keyCode, modifiers: modifiers)
    }

    /// Ordered regular Desktops on the display, excluding fullscreen Spaces.
    static func desktops(for screen: NSScreen) -> Desktops? {
        guard let raw = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue() as? [[String: Any]] else {
            return nil
        }
        guard let currentID = currentSpace(for: screen, in: activeSpaces(in: raw)) else { return nil }
        for display in raw {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            let userSpaces = spaces.filter { ($0["type"] as? Int) == 0 }
            let ids = userSpaces.compactMap {
                ($0["id64"] as? NativeSpaceID) ?? ($0["ManagedSpaceID"] as? NativeSpaceID)
            }
            if let index = ids.firstIndex(of: currentID) {
                return Desktops(index: index, ids: ids)
            }
        }
        return nil
    }

    /// Native space a window lives on.
    static func space(of windowID: WindowID) -> NativeSpaceID? {
        spaces(of: windowID).first
    }

    /// A window can briefly belong to both desktops while it is being carried.
    static func spaces(of windowID: WindowID) -> [NativeSpaceID] {
        let windows = [NSNumber(value: windowID)] as CFArray
        guard let raw = CGSCopySpacesForWindows(CGSMainConnectionID(), 0x7, windows)?.takeRetainedValue() as? [NSNumber] else {
            return []
        }
        return raw.map(\.uint64Value)
    }
}
