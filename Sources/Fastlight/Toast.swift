import AppKit
import ApplicationServices
import SwiftUI

/// A short confirmation at the bottom of the screen ("Copied"), like the
/// system's HUDs. Never takes focus or clicks.
@MainActor
final class Toast {
    static let shared = Toast()
    private var window: NSPanel?
    private var hideWork: DispatchWorkItem?
    /// Bumped per toast, so an older one's fade-out can't hide a newer one.
    private var shown = 0

    func show(_ text: String, symbol: String = "checkmark.circle.fill", duration: TimeInterval = 1.6) {
        let host = NSHostingView(rootView: ToastView(text: text, symbol: symbol))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let panel = window ?? makeWindow()
        window = panel
        panel.contentView = host
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            panel.setFrame(NSRect(x: (area.midX - size.width / 2).rounded(), y: area.minY + area.height * 0.12,
                                  width: size.width, height: size.height), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideWork?.cancel()
        shown += 1
        let mine = shown
        let work = DispatchWorkItem { [weak self, weak panel] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                panel?.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated {
                    guard self?.shown == mine else { return }
                    panel?.orderOut(nil)
                }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func makeWindow() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isReleasedWhenClosed = false
        return p
    }
}

private struct ToastView: View {
    let text: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(text).lineLimit(2)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 460)
        .panelBackground(radius: 18)
        .padding(10)
    }
}

/// Puts text into the app that was in front before the panel opened.
@MainActor
enum Paster {
    private static let askedKey = "fastlight.askedAccessibility"

    static var canPaste: Bool { AXIsProcessTrusted() }

    /// Copies, re-activates `app` and presses ⌘V. Without Accessibility it
    /// can't press keys for the user: it copies, says so, and asks the
    /// system for the permission once.
    static func paste(_ text: String, into app: NSRunningApplication?) {
        copy(text)
        guard canPaste else {
            Toast.shared.show("Copied. Press ⌘V to paste, or allow Fastlight to paste for you in Accessibility settings.",
                              symbol: "doc.on.clipboard", duration: 3)
            if !UserDefaults.standard.bool(forKey: askedKey) {
                UserDefaults.standard.set(true, forKey: askedKey)
                askForAccessibility()
            }
            return
        }
        app?.activate()
        // Give the app a moment to take focus back before the keystroke.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let v: CGKeyCode = 9 // kVK_ANSI_V
            let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// The system prompt that offers to open Accessibility settings.
    static func askForAccessibility() {
        // kAXTrustedCheckOptionPrompt, spelled out: the imported global is
        // a mutable var that strict concurrency won't let us read.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}
