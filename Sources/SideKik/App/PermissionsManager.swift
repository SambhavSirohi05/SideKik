import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import ApplicationServices

/// Manages and checks system permissions for Microphone, Screen Capture, and Accessibility
@MainActor
public final class PermissionsManager: ObservableObject {
    public static let shared = PermissionsManager()

    @Published public var hasMicrophone: Bool = false
    @Published public var hasScreenCapture: Bool = false
    @Published public var hasAccessibility: Bool = false

    private init() {
        checkAllPermissions()
    }

    public func checkAllPermissions() {
        checkMicrophone()
        checkScreenCapture()
        checkAccessibility()
    }

    public func checkMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        self.hasMicrophone = (status == .authorized)
        AppState.shared.hasMicrophonePermission = self.hasMicrophone
    }

    public func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in
                self?.hasMicrophone = granted
                AppState.shared.hasMicrophonePermission = granted
            }
        }
    }

    public func checkScreenCapture() {
        let granted = CGPreflightScreenCaptureAccess()
        self.hasScreenCapture = granted
        AppState.shared.hasScreenCapturePermission = granted
    }

    public func requestScreenCapture() {
        let granted = CGRequestScreenCaptureAccess()
        self.hasScreenCapture = granted
        AppState.shared.hasScreenCapturePermission = granted
        if !granted {
            openSystemSettings(pane: "Privacy_ScreenCapture")
        }
    }

    public func checkAccessibility() {
        let granted = AXIsProcessTrusted()
        self.hasAccessibility = granted
        AppState.shared.hasAccessibilityPermission = granted
    }

    public func requestAccessibility() {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        self.hasAccessibility = granted
        AppState.shared.hasAccessibilityPermission = granted
        if !granted {
            openSystemSettings(pane: "Privacy_Accessibility")
        }
    }

    public func openSystemSettings(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
