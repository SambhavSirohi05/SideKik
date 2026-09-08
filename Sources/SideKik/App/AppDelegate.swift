import Cocoa
import SwiftUI
import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public static private(set) var shared: AppDelegate?

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var globalHotKeyMonitor: Any?
    private var localHotKeyMonitor: Any?
    private var isHotkeyHeld: Bool = false

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // Run as menu bar accessory app (no Dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Load saved configuration from ~/.config/sidekik/config.json
        AppState.shared.loadConfig()

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

        // Check initial system permissions and show onboarding if needed
        PermissionsManager.shared.checkAllPermissions()
        showOnboardingIfNeeded()
    }

    private var onboardingWindow: NSWindow?

    public func showOnboardingIfNeeded() {
        let pm = PermissionsManager.shared
        if !AppState.shared.hasCompletedOnboarding && (!pm.hasMicrophone || !pm.hasScreenCapture || !pm.hasAccessibility) {
            showOnboardingWindow()
        }
    }

    public func showOnboardingWindow() {
        if onboardingWindow != nil {
            onboardingWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SideKik Permissions Setup"
        window.center()
        window.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: PermissionsOnboardingView { [weak self, weak window] in
            AppState.shared.hasCompletedOnboarding = true
            AppState.shared.saveConfig()
            window?.close()
            self?.onboardingWindow = nil
        })
        window.contentView = hostingView
        self.onboardingWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
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
        popover.contentSize = NSSize(width: 360, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView())
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover = self.popover else { return }

        if AppState.shared.companionState == .speaking || AppState.shared.isTourActive {
            CompanionOrchestrator.shared.interruptSpeech(resumeListening: false)
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    public func closePopover() {
        if popover?.isShown == true {
            popover?.performClose(nil)
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
