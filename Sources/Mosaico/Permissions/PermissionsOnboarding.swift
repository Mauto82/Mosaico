import AppKit
import SwiftUI

/// Shows the onboarding window until the Accessibility permission is
/// granted, then calls `onGranted` (without needing to restart the app).
final class PermissionsOnboarding {
    private let onGranted: () -> Void
    private var window: NSWindow?
    private var timer: Timer?

    init(onGranted: @escaping () -> Void) {
        self.onGranted = onGranted
    }

    func begin() {
        // System prompt (only once)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        showWindow()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, AXIsProcessTrusted() else { return }
            self.timer?.invalidate()
            self.timer = nil
            self.window?.close()
            self.window = nil
            self.onGranted()
        }
    }

    private func showWindow() {
        let view = OnboardingView()
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = tr("Welcome to Mosaico")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct OnboardingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.split.2x2")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text(tr("Mosaico arranges your windows"))
                .font(.title2.bold())

            Text(markdown: tr("To manage other apps' windows, macOS requires the **Accessibility** permission.\n\nOpen System Settings → Privacy & Security → Accessibility and turn on Mosaico. This window closes by itself as soon as the permission is granted."))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Button(tr("Open System Settings")) {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
    }
}

private extension Text {
    /// Inline markdown (bold) from an already translated string, keeping line breaks.
    init(markdown: String) {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        self.init((try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown))
    }
}
