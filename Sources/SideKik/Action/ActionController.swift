import Foundation
import AppKit
import CoreGraphics

/// Executes on-screen physical interactions (clicks, keystrokes) and off-screen automation tasks (shell, app launches)
@MainActor
public final class ActionController: Sendable {
    public static let shared = ActionController()

    private init() {}

    // MARK: - On-Screen Physical Interactions

    /// Simulates a mouse click at specific screen coordinates (top-left origin)
    public func click(at screenPoint: CGPoint, targetAppName: String? = nil) {
        if let appName = targetAppName {
            _ = launchApplication(named: appName)
            usleep(60000) // 60ms for window to become active
        }

        let source = CGEventSource(stateID: .hidSystemState)

        // Warp mouse cursor to target point so apps register the cursor hover
        CGWarpMouseCursorPosition(screenPoint)

        let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: screenPoint, mouseButton: .left)
        moveEvent?.post(tap: .cghidEventTap)

        usleep(40000) // 40ms

        // Mouse down with single-click clickState = 1
        if let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: screenPoint, mouseButton: .left) {
            mouseDown.setIntegerValueField(.mouseEventClickState, value: 1)
            mouseDown.post(tap: .cghidEventTap)
        }

        // Brief delay before mouse up
        usleep(60000) // 60ms

        // Mouse up with single-click clickState = 1
        if let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: screenPoint, mouseButton: .left) {
            mouseUp.setIntegerValueField(.mouseEventClickState, value: 1)
            mouseUp.post(tap: .cghidEventTap)
        }
    }

    /// Types text into the currently active element
    public func typeText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V (Paste)
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 9 // 'v' key in macOS

        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }

        usleep(30000)

        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }
    }

    /// Presses the Return / Enter key
    public func pressReturn() {
        let source = CGEventSource(stateID: .hidSystemState)
        let returnKey: CGKeyCode = 36 // Return key

        if let down = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true) {
            down.post(tap: .cghidEventTap)
        }
        usleep(30000)
        if let up = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false) {
            up.post(tap: .cghidEventTap)
        }
    }

    /// Simulates mouse wheel scrolling at an optional screen coordinate (vertical and horizontal timeline scrubbing)
    public func scroll(deltaX: Int32 = 0, deltaY: Int32 = -5, at point: CGPoint? = nil) {
        if let target = point {
            CGWarpMouseCursorPosition(target)
            usleep(30000)
        }

        // wheel1: deltaY (positive is up, negative is down)
        // wheel2: deltaX (positive is left, negative is right)
        if let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ) {
            scrollEvent.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Off-Screen Tasks Execution

    /// Opens or switches to an application by name
    public func launchApplication(named appName: String) -> Bool {
        // 1. Open / switch via macOS /usr/bin/open -a (brings window to front reliably)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appName]
        try? process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            return true
        }

        // 2. If already running, activate
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.localizedCaseInsensitiveContains(appName) == true
        }) {
            app.activate()
            return true
        }

        // 3. Fallback to bundle identifier
        if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.\(appName.lowercased())") ??
                        NSWorkspace.shared.urlForApplication(withBundleIdentifier: appName) {
            NSWorkspace.shared.openApplication(at: appUrl, configuration: NSWorkspace.OpenConfiguration())
            return true
        }

        return false
    }

    /// Executes shell command and returns output
    public func executeShellCommand(_ command: String) async -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "Execution failed: \(error.localizedDescription)"
        }
    }
}
