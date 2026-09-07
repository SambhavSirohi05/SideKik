import Cocoa
import SwiftUI
import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var globalHotKeyMonitor: Any?
    private var localHotKeyMonitor: Any?
    private var isHotkeyHeld: Bool = false

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as menu bar accessory app (no Dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Load saved API keys from Keychain
        if let geminiKey = KeychainHelper.shared.get(key: "gemini_api_key") {
            AppState.shared.geminiApiKey = geminiKey
        }
        if let sarvamKey = KeychainHelper.shared.get(key: "sarvam_api_key") {
            AppState.shared.sarvamApiKey = sarvamKey
        }

        // Initialize status item in menu bar
        setupStatusItem()

        // Show transparent companion overlay panel
        OverlayPanel.shared.showOverlay()

        // Start agent IPC loopback server
        AgentNotificationServer.shared.start()

        // Install sidekik CLI tool into ~/.local/bin
        AgentCLIHandler.shared.installCLIToolIfNeeded()

        // Register push-to-talk hotkey (Control + Option)
        setupPushToTalkHotKey()

        // Check initial system permissions
        PermissionsManager.shared.checkAllPermissions()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalHotKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localHotKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        AgentNotificationServer.shared.stop()
    }

    // MARK: - Menu Bar Setup
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "SideKik")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 440)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView())
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover = self.popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Push-to-Talk Hotkey (Control + Option)
    private func setupPushToTalkHotKey() {
        // Global monitor for when other apps are active
        globalHotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            Task { @MainActor in
                self?.handleModifierFlags(event.modifierFlags)
            }
        }

        // Local monitor for when SideKik popover is active
        localHotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleModifierFlags(event.modifierFlags)
            return event
        }
    }

    private func handleModifierFlags(_ flags: NSEvent.ModifierFlags) {
        let isControl = flags.contains(.control)
        let isOption = flags.contains(.option)
        let triggerHeld = isControl && isOption

        if triggerHeld && !isHotkeyHeld {
            isHotkeyHeld = true
            CompanionOrchestrator.shared.startPushToTalk()
        } else if !triggerHeld && isHotkeyHeld {
            isHotkeyHeld = false
            CompanionOrchestrator.shared.stopPushToTalk()
        }
    }
}
