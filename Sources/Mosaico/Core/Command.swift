import Foundation

enum Direction: String, Codable, CaseIterable {
    case west, south, north, east
}

/// All executable actions, invoked from hotkey and menubar.
enum Command: Codable, Equatable, Hashable {
    case focus(Direction)
    case focusDisplay(Direction)      // west/east only
    case swap(Direction)
    case warp(Direction)
    case rotate                       // 270°, like yabai --rotate 270
    case mirrorX
    case mirrorY
    case balance
    case toggleFloat
    case toggleZoom
    case moveToDisplay(Direction)     // west/east only, then focus follows
    case moveToWorkspace(Int)
    case moveToWorkspacePrev
    case moveToWorkspaceNext
    case pauseResume
    case retileAll

    /// Title for menu and settings.
    var title: String {
        switch self {
        case .focus(let d): return tr("Focus %@", d.title)
        case .focusDisplay(let d): return tr("Focus Display %@", d.title)
        case .swap(let d): return tr("Swap %@", d.title)
        case .warp(let d): return tr("Warp %@", d.title)
        case .rotate: return tr("Rotate Layout")
        case .mirrorX: return tr("Mirror X Axis")
        case .mirrorY: return tr("Mirror Y Axis")
        case .balance: return tr("Balance Windows")
        case .toggleFloat: return tr("Toggle Float")
        case .toggleZoom: return tr("Zoom/Restore")
        case .moveToDisplay(let d): return tr("Move to Display %@", d.title)
        case .moveToWorkspace(let n): return tr("Move to Space %d", n)
        case .moveToWorkspacePrev: return tr("Move to Previous Space")
        case .moveToWorkspaceNext: return tr("Move to Next Space")
        case .pauseResume: return tr("Pause/Resume Tiling")
        case .retileAll: return tr("Re-tile All")
        }
    }
}

extension Direction {
    var title: String {
        switch self {
        case .west: return tr("West")
        case .south: return tr("South")
        case .north: return tr("North")
        case .east: return tr("East")
        }
    }
}
