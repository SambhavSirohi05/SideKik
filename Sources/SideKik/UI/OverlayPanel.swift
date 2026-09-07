import Foundation
import AppKit
import SwiftUI

/// Fullscreen non-activating transparent NSPanel hosting the companion overlay across all spaces
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

        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hostingView = NSHostingView(rootView: CompanionCursorView())
        hostingView.frame = primaryFrame
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView
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
