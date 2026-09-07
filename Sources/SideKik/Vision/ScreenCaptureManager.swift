import Foundation
import AppKit
import ScreenCaptureKit
import CoreGraphics
import ImageIO

public struct ScreenCaptureResult: Sendable {
    public let imageBase64: String
    public let screenFrame: NSRect
    public let displayID: CGDirectDisplayID
    public let pixelWidth: Int
    public let pixelHeight: Int
}

/// Screen capture orchestrator using hardware-accelerated ScreenCaptureKit
public final class ScreenCaptureManager: Sendable {
    public static let shared = ScreenCaptureManager()

    private init() {}

    /// Captures the screen currently containing the mouse cursor
    public func captureActiveDisplay() async throws -> ScreenCaptureResult {
        // Find screen under mouse
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard let currentScreen = screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? screens.first else {
            throw NSError(domain: "ScreenCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No active display found."])
        }

        let displayIDNumber = currentScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let targetDisplayID = CGDirectDisplayID(displayIDNumber?.uint32Value ?? CGMainDisplayID())

        // Try hardware-accelerated ScreenCaptureKit first
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            if let scDisplay = content.displays.first(where: { $0.displayID == targetDisplayID }) ?? content.displays.first {
                let filter = SCContentFilter(display: scDisplay, excludingApplications: [], exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.showsCursor = false
                let scale = currentScreen.backingScaleFactor > 0 ? currentScreen.backingScaleFactor : 2.0
                config.width = Int(CGFloat(scDisplay.width) * scale)
                config.height = Int(CGFloat(scDisplay.height) * scale)
                config.scalesToFit = false

                let rawCGImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let resizedImage = resizeCGImage(rawCGImage, maxDimension: 1280)
                if let jpegData = jpegDataFromCGImage(resizedImage, compressionQuality: 0.75) {
                    return ScreenCaptureResult(
                        imageBase64: jpegData.base64EncodedString(),
                        screenFrame: currentScreen.frame,
                        displayID: targetDisplayID,
                        pixelWidth: resizedImage.width,
                        pixelHeight: resizedImage.height
                    )
                }
            }
        } catch {
            print("ScreenCaptureKit notice: \(error.localizedDescription), using native display capture fallback")
        }

        // Seamless native macOS fallback
        return try captureViaCLI(screen: currentScreen, displayID: targetDisplayID)
    }

    private func captureViaCLI(screen: NSScreen, displayID: CGDirectDisplayID) throws -> ScreenCaptureResult {
        let tempPath = "/tmp/sidekik_screen_\(UUID().uuidString).jpg"
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-t", "jpg", tempPath]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let data = try? Data(contentsOf: URL(fileURLWithPath: tempPath)),
              !data.isEmpty else {
            throw NSError(domain: "ScreenCapture", code: 5, userInfo: [NSLocalizedDescriptionKey: "Native display capture failed."])
        }

        return ScreenCaptureResult(
            imageBase64: data.base64EncodedString(),
            screenFrame: screen.frame,
            displayID: displayID,
            pixelWidth: Int(screen.frame.width),
            pixelHeight: Int(screen.frame.height)
        )
    }

    private func resizeCGImage(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
        let originalWidth = CGFloat(image.width)
        let originalHeight = CGFloat(image.height)

        if originalWidth <= maxDimension && originalHeight <= maxDimension {
            return image
        }

        let scale = min(maxDimension / originalWidth, maxDimension / originalHeight)
        let newWidth = Int(originalWidth * scale)
        let newHeight = Int(originalHeight * scale)

        guard let colorSpace = image.colorSpace,
              let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: image.bitsPerComponent,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: image.bitmapInfo.rawValue
              ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage() ?? image
    }

    private func jpegDataFromCGImage(_ image: CGImage, compressionQuality: CGFloat) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return mutableData as Data
    }
}
