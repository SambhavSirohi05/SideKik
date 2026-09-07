import Foundation
import AppKit
import ApplicationServices

public struct AccessibleElement: Sendable {
    public let role: String
    public let title: String
    public let elementDescription: String
    public let bounds: NSRect
}

/// Manages interaction and spatial queries using the macOS Accessibility API (AXUIElement)
public final class AccessibilityManager: Sendable {
    public static let shared = AccessibilityManager()

    private init() {}

    /// Finds the window frame of a specified application by name
    public func findWindowFrame(forAppName appName: String) -> NSRect? {
        let runningApps = NSWorkspace.shared.runningApplications
        guard let app = runningApps.first(where: {
            ($0.localizedName?.localizedCaseInsensitiveContains(appName) == true) ||
            ($0.bundleIdentifier?.localizedCaseInsensitiveContains(appName) == true)
        }) else {
            return nil
        }

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: AnyObject?
        let status = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard status == .success, let windows = windowsRef as? [AXUIElement], let mainWindow = windows.first else {
            return nil
        }

        var positionRef: AnyObject?
        var sizeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(mainWindow, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(mainWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posValue = positionRef, let sizeValue = sizeRef else {
            return nil
        }

        var axPoint = CGPoint.zero
        var axSize = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &axPoint),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &axSize) else {
            return nil
        }

        // Convert AX coordinate (origin at top-left of primary screen) to Cocoa coordinate (origin at bottom-left)
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 1080.0
        let cocoaY = primaryScreenHeight - (axPoint.y + axSize.height)

        return NSRect(x: axPoint.x, y: cocoaY, width: axSize.width, height: axSize.height)
    }

    /// Brings an application to the foreground
    public func activateApplication(named appName: String) {
        let runningApps = NSWorkspace.shared.runningApplications
        if let app = runningApps.first(where: {
            ($0.localizedName?.localizedCaseInsensitiveContains(appName) == true) ||
            ($0.bundleIdentifier?.localizedCaseInsensitiveContains(appName) == true)
        }) {
            app.activate()
        }
    }

    /// Traverses the frontmost application's accessibility tree to find candidate interactive controls
    public func queryFocusedElements() -> [AccessibleElement] {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return [] }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var focusedElementRef: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementRef) == .success,
              let element = focusedElementRef else {
            return []
        }

        let axElem = element as! AXUIElement
        var elements: [AccessibleElement] = []

        if let accessible = extractElement(axElem) {
            elements.append(accessible)
        }

        return elements
    }

    private func extractElement(_ element: AXUIElement) -> AccessibleElement? {
        var roleRef: AnyObject?
        var titleRef: AnyObject?
        var descRef: AnyObject?
        var posRef: AnyObject?
        var sizeRef: AnyObject?

        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)

        guard let role = roleRef as? String,
              let posVal = posRef, let sizeVal = sizeRef else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)

        let title = (titleRef as? String) ?? ""
        let desc = (descRef as? String) ?? ""

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080.0
        let cocoaY = primaryHeight - (point.y + size.height)

        return AccessibleElement(
            role: role,
            title: title,
            elementDescription: desc,
            bounds: NSRect(x: point.x, y: cocoaY, width: size.width, height: size.height)
        )
    }
}
