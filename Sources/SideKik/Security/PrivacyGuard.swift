import Foundation
import AppKit

/// Inspects frontmost applications and windows to prevent capturing sensitive data
public final class PrivacyGuard: Sendable {
    public static let shared = PrivacyGuard()

    private let sensitiveBundleIdentifiers: Set<String> = [
        "com.agilebits.onepassword",
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.dashlane.dashlane",
        "com.keepassxc.keepassxc",
        "org.keepassx.keepassx",
        "in.sinew.enpass-desktop"
    ]

    private let sensitiveTitleKeywords: [String] = [
        "private browsing",
        "incognito",
        "inprivate",
        "password",
        "bitwarden",
        "1password"
    ]

    private init() {}

    public struct PrivacyCheckResult: Sendable {
        public let isAllowed: Bool
        public let reason: String?
        public let appName: String
    }

    /// Verifies if screen capture is safe
    public func validateScreenCapture() -> PrivacyCheckResult {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return PrivacyCheckResult(isAllowed: true, reason: nil, appName: "Desktop")
        }

        let appName = frontApp.localizedName ?? "Application"
        let bundleId = frontApp.bundleIdentifier?.lowercased() ?? ""

        // Check bundle identifiers
        for sensitiveId in sensitiveBundleIdentifiers {
            if bundleId.contains(sensitiveId) {
                return PrivacyCheckResult(
                    isAllowed: false,
                    reason: "Protected password manager (\(appName)) detected.",
                    appName: appName
                )
            }
        }

        // Check active window title if accessible
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        if let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            for window in windowList {
                if let ownerPID = window[kCGWindowOwnerPID as String] as? Int32, ownerPID == frontApp.processIdentifier {
                    if let windowTitle = window[kCGWindowName as String] as? String {
                        let lowerTitle = windowTitle.lowercased()
                        for keyword in sensitiveTitleKeywords {
                            if lowerTitle.contains(keyword) {
                                return PrivacyCheckResult(
                                    isAllowed: false,
                                    reason: "Protected window title '\(windowTitle)' indicates private session.",
                                    appName: appName
                                )
                            }
                        }
                    }
                }
            }
        }

        return PrivacyCheckResult(isAllowed: true, reason: nil, appName: appName)
    }
}
