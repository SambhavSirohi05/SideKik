import Foundation
import AppKit
import SwiftUI

/// Fullscreen transparent NSPanel hosting the companion overlay across all spaces.
/// Permanently non-interactive (ignoresMouseEvents = true) so it NEVER blocks user clicks or scroll events on any app.
public final class OverlayPanel: NSPanel {
    public static let shared = OverlayPanel()

    private init() {
        let primaryFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

        super.init(
            contentRect: primaryFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Make window transparent and completely non-interactive
        self.isOpaque = false
        self.backgroundColor = .clear
        // Use overlayWindow level (102) rather than .floating (3) so macOS WindowServer does NOT treat this
        // as an active window palette, allowing fullscreen apps to cleanly auto-hide their menubar and titlebar.
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        self.ignoresMouseEvents = true  // 100% click-through & scroll-through: never blocks user clicks or scrolling!
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .fullScreenDisallowsTiling]
        self.isReleasedWhenClosed = false
        self.hasShadow = false
        self.hidesOnDeactivate = false
        self.animationBehavior = .none
        self.sharingType = .none

        let hostingView = NSHostingView(rootView: CompanionCursorView())
        hostingView.frame = primaryFrame
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView
    }

    override public var canBecomeKey: Bool {
        return false
    }

    override public var canBecomeMain: Bool {
        return false
    }

    /// Repositions overlay to fit current screen setup
    public func updateFrame() {
        if let mainScreen = NSScreen.main {
            self.setFrame(mainScreen.frame, display: true)
        }
    }

    public func showOverlay() {
        updateFrame()
        self.orderFrontRegardless()
    }
}
