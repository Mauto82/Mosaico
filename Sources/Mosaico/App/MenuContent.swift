import SwiftUI

/// Menubar menu — same structure as YabaiMenu, but each action
/// calls the WindowManager in-process instead of shelling out to yabai.
struct MenuContent: View {
    @ObservedObject private var menuState = MenuState.shared
    @ObservedObject private var loginItem = LoginItem.shared
    // Observed so a language change rebuilds the menu
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        Section(tr("Focus Window")) {
            cmd(.focus(.south), "⌥J")
            cmd(.focus(.north), "⌥K")
            cmd(.focus(.west), "⌥H")
            cmd(.focus(.east), "⌥L")
        }

        Divider()

        Section(tr("Focus Display")) {
            cmd(.focusDisplay(.west), "⌥S")
            cmd(.focusDisplay(.east), "⌥G")
        }

        Divider()

        Section(tr("Layout")) {
            cmd(.rotate, "⇧⌥R")
            cmd(.mirrorY, "⇧⌥Y")
            cmd(.mirrorX, "⇧⌥X")
            cmd(.toggleFloat, "⇧⌥T")
            cmd(.toggleZoom, "⇧⌥M")
            cmd(.balance, "⇧⌥E")
        }

        Divider()

        Section(tr("Swap Windows")) {
            cmd(.swap(.south), "⇧⌥J")
            cmd(.swap(.north), "⇧⌥K")
            cmd(.swap(.west), "⇧⌥H")
            cmd(.swap(.east), "⇧⌥L")
        }

        Divider()

        Section(tr("Warp Windows")) {
            cmd(.warp(.south), "⌃⌥J")
            cmd(.warp(.north), "⌃⌥K")
            cmd(.warp(.west), "⌃⌥H")
            cmd(.warp(.east), "⌃⌥L")
        }

        Divider()

        Section(tr("Move Window")) {
            cmd(.moveToDisplay(.west), "⇧⌥S")
            cmd(.moveToDisplay(.east), "⇧⌥G")
        }

        Divider()

        Section("Mosaico") {
            Menu(tr("Exclude Window")) {
                // ✓ = excluded from tiling; click to toggle
                ForEach(menuState.windows) { info in
                    Button("\(info.isExcluded ? "✓" : "　")  \(info.appName) — \(info.title)") {
                        WindowManager.shared.toggleExclusion(info.id)
                    }
                }

                if !menuState.staleRules.isEmpty {
                    Divider()
                    Section(tr("Saved rules (click to remove)")) {
                        ForEach(menuState.staleRules) { rule in
                            Button("✓  \(appDisplayName(for: rule.bundleID)) — \(rule.title)") {
                                WindowManager.shared.removeExclusionRule(rule)
                            }
                        }
                    }
                }
            }

            Button("⌃⌥Q  \(menuState.isPaused ? tr("▶ Resume Tiling") : tr("⏸ Pause Tiling"))") {
                WindowManager.shared.perform(.pauseResume)
            }
            cmd(.retileAll, "⌃⌥R")

            Button("\(loginItem.isEnabled ? "✓" : "　")  \(tr("Launch at Login"))") {
                loginItem.toggle()
            }

            Button(tr("Settings…")) {
                SettingsWindowController.shared.show()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        Divider()

        Button(tr("Quit Mosaico")) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func cmd(_ command: Command, _ shortcut: String) -> some View {
        Button("\(shortcut)  \(command.title)") {
            WindowManager.shared.perform(command)
        }
    }

    private func appDisplayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }
}
